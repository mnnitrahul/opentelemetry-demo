"""SQS Consumer Lambda - triggered by SQS queue, writes to DynamoDB."""
import json, os, time, boto3
from aws_xray_sdk.core import xray_recorder, patch_all
patch_all()
dynamodb = boto3.resource('dynamodb')
TABLE = os.environ.get('DYNAMODB_TABLE_NAME', 'otel-demo-orders')

def handler(event, context):
    table = dynamodb.Table(TABLE)
    for record in event.get('Records', []):
        body = json.loads(record['body'])
        # If from SNS, unwrap the Message
        msg = json.loads(body['Message']) if 'Message' in body else body
        table.put_item(Item={
            'orderId': f"sqs-{msg.get('orderId','unknown')}-{int(time.time())}",
            'source': 'sqs-consumer', 'timestamp': str(int(time.time())),
            'data': json.dumps(msg)
        })
    return {'statusCode': 200}
