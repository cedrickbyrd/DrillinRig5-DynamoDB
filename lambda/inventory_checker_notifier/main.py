import os
import json
import boto3
from datetime import datetime, timedelta

sns_client = boto3.client('sns')
dynamodb_client = boto3.client('dynamodb')

SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
DEFAULT_MIN_QUANTITY = int(os.environ.get('DEFAULT_MIN_QUANTITY', 5)) # Default if not set in DDB
DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME') # Need this if we update last_notified_timestamp
NOTIFICATION_COOLDOWN_HOURS = 24 # Avoid sending too many notifications for the same item

def lambda_handler(event, context):
    print(f"Received event: {json.dumps(event)}")

    if not SNS_TOPIC_ARN:
        print("SNS_TOPIC_ARN not set in environment variables. Cannot send notifications.")
        return {'statusCode': 500, 'body': 'SNS Topic ARN not configured.'}

    if not DYNAMODB_TABLE_NAME:
        print("DYNAMODB_TABLE_NAME not set in environment variables. Cannot update last_notified_timestamp.")
        # We can still proceed with notifications, but without cooldown management in DDB
        pass

    for record in event['Records']:
        if record['eventName'] == 'MODIFY' or record['eventName'] == 'INSERT':
            new_image = record['dynamodb'].get('NewImage')

            if not new_image:
                print("No NewImage found in record, skipping.")
                continue

            # Parse item details
            item_id = new_image.get('item_id', {}).get('S')
            item_name = new_image.get('item_name', {}).get('S', 'Unknown Item')
            current_quantity_str = new_image.get('quantity', {}).get('N')
            minimum_quantity_str = new_image.get('minimum_quantity', {}).get('N')
            last_notified_timestamp_str = new_image.get('last_notified_timestamp', {}).get('N') # Stored as epoch string

            if not item_id or not current_quantity_str:
                print(f"Missing item_id or quantity for record: {json.dumps(record)}. Skipping.")
                continue

            try:
                current_quantity = int(current_quantity_str)
                minimum_quantity = int(minimum_quantity_str) if minimum_quantity_str else DEFAULT_MIN_QUANTITY
            except (ValueError, TypeError) as e:
                print(f"Error parsing quantity for item {item_id}: {e}. Skipping.")
                continue

            print(f"Checking item: {item_name} (ID: {item_id}), Current: {current_quantity}, Min: {minimum_quantity}")

            if current_quantity <= minimum_quantity:
                # Check cooldown period
                current_time_epoch = int(datetime.utcnow().timestamp())
                last_notified_time = 0
                if last_notified_timestamp_str:
                    try:
                        last_notified_time = int(last_notified_timestamp_str)
                    except (ValueError, TypeError):
                        print(f"Invalid last_notified_timestamp for {item_id}: {last_notified_timestamp_str}. Ignoring cooldown.")

                # Only notify if cooldown has passed or it's the first time
                if (current_time_epoch - last_notified_time) >= (NOTIFICATION_COOLDOWN_HOURS * 3600):
                    message = (
                        f"LOW INVENTORY ALERT!\n\n"
                        f"Item: {item_name}\n"
                        f"Item ID: {item_id}\n"
                        f"Current Quantity: {current_quantity}\n"
                        f"Minimum Threshold: {minimum_quantity}\n\n"
                        f"Please reorder this item soon."
                    )
                    subject = f"Low Inventory Alert: {item_name} (ID: {item_id})"

                    try:
                        sns_client.publish(
                            TopicArn=SNS_TOPIC_ARN,
                            Message=message,
                            Subject=subject
                        )
                        print(f"Successfully published SNS alert for item {item_id}")

                        # Update last_notified_timestamp in DynamoDB
                        if DYNAMODB_TABLE_NAME:
                            try:
                                dynamodb_client.update_item(
                                    TableName=DYNAMODB_TABLE_NAME,
                                    Key={'item_id': {'S': item_id}},
                                    UpdateExpression="SET last_notified_timestamp = :ts",
                                    ExpressionAttributeValues={
                                        ':ts': {'N': str(current_time_epoch)}
                                    }
                                )
                                print(f"Updated last_notified_timestamp for item {item_id}")
                            except Exception as db_err:
                                print(f"Error updating last_notified_timestamp for {item_id}: {db_err}")

                    except Exception as e:
                        print(f"Error publishing SNS alert for item {item_id}: {e}")
                else:
                    print(f"Skipping notification for {item_id} due to cooldown period. Last notified: {datetime.fromtimestamp(last_notified_time).isoformat()}")
            else:
                print(f"Quantity for {item_id} ({current_quantity}) is above minimum {minimum_quantity}. No alert needed.")
        else:
            print(f"Skipping non-MODIFY/INSERT event: {record['eventName']}")

    return {'statusCode': 200, 'body': 'Processing complete'}
