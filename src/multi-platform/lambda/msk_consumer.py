"""MSK Consumer Lambda - triggered by MSK Serverless, writes to DynamoDB."""
import json, os, base64, time, boto3
from aws_xray_sdk.core import xray_recorder, patch_all
patch_all()

dynamodb = boto3.resource('dynamodb')
TABLE = os.environ.get('DYNAMODB_TABLE_NAME', 'otel-demo-orders')

def handler(event, context):
    table = dynamodb.Table(TABLE)
    for topic, partitions in event.get('records', {}).items():
        for record in partitions:
            value = base64.b64decode(record['value']).decode('utf-8')
            data = json.loads(value)
            table.put_item(Item={
                'orderId': f"msk-{data.get('orderId','unknown')}",
                'source': 'msk-consumer', 'timestamp': str(int(time.time())),
                'originalOrder': value
            })
    return {'statusCode': 200, 'body': f'Processed {len(event.get("records", {}))} topics'}
