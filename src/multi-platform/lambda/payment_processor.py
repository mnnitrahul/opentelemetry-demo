"""
Payment Processor Lambda Function.
Receives payment requests via API Gateway, writes to DynamoDB, returns confirmation.
Instrumented with OpenTelemetry for X-Ray tracing.
"""
import json
import os
import uuid
import time
import boto3
from aws_xray_sdk.core import xray_recorder, patch_all

# Patch AWS SDK for X-Ray tracing
patch_all()

dynamodb = boto3.resource('dynamodb')
TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', 'otel-demo-orders')


def handler(event, context):
    """Lambda handler for payment processing."""
    table = dynamodb.Table(TABLE_NAME)

    # Parse request body
    body = {}
    if event.get('body'):
        body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']

    payment_id = str(uuid.uuid4())
    amount = body.get('amount', 0)
    currency = body.get('currency', 'USD')
    order_id = body.get('order_id', 'unknown')

    # Write payment record to DynamoDB
    item = {
        'orderId': f'payment-{payment_id}',
        'paymentId': payment_id,
        'orderRef': order_id,
        'amount': str(amount),
        'currency': currency,
        'status': 'COMPLETED',
        'timestamp': str(int(time.time())),
        'platform': 'lambda'
    }
    table.put_item(Item=item)

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'paymentId': payment_id,
            'status': 'COMPLETED',
            'amount': amount,
            'currency': currency,
            'platform': 'lambda'
        })
    }
