"""Kinesis Consumer Lambda - triggered by Kinesis stream, writes to DynamoDB."""
import json, os, base64, time, boto3
from aws_xray_sdk.core import xray_recorder, patch_all
patch_all()
dynamodb = boto3.resource('dynamodb')
TABLE = os.environ.get('DYNAMODB_TABLE_NAME', 'otel-demo-orders')

def handler(event, context):
    table = dynamodb.Table(TABLE)
    for record in event.get('Records', []):
        data = json.loads(base64.b64decode(record['kinesis']['data']).decode('utf-8'))
        table.put_item(Item={
            'orderId': f"kinesis-{data.get('orderId','unknown')}-{int(time.time())}",
            'source': 'kinesis-consumer', 'timestamp': str(int(time.time())),
            'data': json.dumps(data)
        })
    return {'statusCode': 200}
