"""SNS Consumer Lambda - triggered by SNS topic, writes to DynamoDB."""
import json, os, time, boto3
from aws_xray_sdk.core import xray_recorder, patch_all
patch_all()
dynamodb = boto3.resource('dynamodb')
TABLE = os.environ.get('DYNAMODB_TABLE_NAME', 'otel-demo-orders')

def handler(event, context):
    table = dynamodb.Table(TABLE)
    for record in event.get('Records', []):
        msg = json.loads(record['Sns']['Message'])
        table.put_item(Item={
            'orderId': f"sns-{msg.get('orderId','unknown')}-{int(time.time())}",
            'source': 'sns-consumer', 'timestamp': str(int(time.time())),
            'data': json.dumps(msg)
        })
    return {'statusCode': 200}
