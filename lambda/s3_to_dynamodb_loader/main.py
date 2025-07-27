import os
import json
import csv
import io
import boto3

s3_client = boto3.client('s3')
dynamodb_client = boto3.client('dynamodb')

DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')

def lambda_handler(event, context):
    print(f"Received S3 event: {json.dumps(event)}")

    if not DYNAMODB_TABLE_NAME:
        print("DYNAMODB_TABLE_NAME not set in environment variables.")
        return {'statusCode': 500, 'body': 'DynamoDB Table Name not configured.'}

    for record in event['Records']:
        bucket_name = record['s3']['bucket']['name']
        file_key = record['s3']['object']['key']

        print(f"Processing file {file_key} from bucket {bucket_name}")

        try:
            # Get the file from S3
            response = s3_client.get_object(Bucket=bucket_name, Key=file_key)
            file_content = response['Body'].read().decode('utf-8')

            # Process CSV content
            csv_reader = csv.reader(io.StringIO(file_content))
            header = next(csv_reader) # Skip header row

            processed_items = 0
            for row in csv_reader:
                if len(row) < 4: # Assuming item_id, item_name, quantity, minimum_quantity
                    print(f"Skipping malformed row: {row}")
                    continue

                item_id = row[0].strip()
                item_name = row[1].strip()
                quantity = row[2].strip()
                minimum_quantity = row[3].strip()

                try:
                    # Put/Update item in DynamoDB
                    dynamodb_client.put_item(
                        TableName=DYNAMODB_TABLE_NAME,
                        Item={
                            'item_id': {'S': item_id},
                            'item_name': {'S': item_name},
                            'quantity': {'N': quantity},
                            'minimum_quantity': {'N': minimum_quantity},
                            'last_notified_timestamp': {'N': '0'} # Initialize to 0 for new items
                        }
                    )
                    processed_items += 1
                except Exception as db_err:
                    print(f"Error putting item {item_id} into DynamoDB: {db_err}")

            print(f"Successfully processed {processed_items} items from {file_key}")

        except Exception as e:
            print(f"Error processing file {file_key}: {e}")
            # Consider moving the file to a 'failed' prefix or sending a notification

    return {'statusCode': 200, 'body': 'S3 file processing complete'}
