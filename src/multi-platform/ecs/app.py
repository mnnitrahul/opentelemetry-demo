"""
Order Processor - ECS Service
Uses vanilla OTel SDK → local collector sidecar → X-Ray.
Calls Lambda via API Gateway, inventory service via ALB.
Publishes order events to MSK Serverless.
"""
import json
import os
import uuid
import time
import logging

import boto3
import requests
from flask import Flask, request, jsonify
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.instrumentation.botocore import BotocoreInstrumentor

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SERVICE_NAME = os.environ.get('OTEL_SERVICE_NAME', 'multi-order-processor')
TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', 'otel-demo-orders')
BUCKET_NAME = os.environ.get('S3_BUCKET_NAME', '')
PAYMENT_URL = os.environ.get('PAYMENT_PROCESSOR_URL', '')
INVENTORY_URL = os.environ.get('INVENTORY_SERVICE_URL', '')
MSK_BOOTSTRAP = os.environ.get('MSK_BOOTSTRAP', '')

# OTel SDK → local collector sidecar on localhost:4318
resource = Resource.create({"service.name": SERVICE_NAME, "service.namespace": "otel-demo-multi"})
provider = TracerProvider(resource=resource)
# Sidecar collector listens on localhost:4318
exporter = OTLPSpanExporter(endpoint="http://localhost:4318/v1/traces")
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(SERVICE_NAME)

BotocoreInstrumentor().instrument()
RequestsInstrumentor().instrument()

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

dynamodb = boto3.resource('dynamodb', region_name=os.environ.get('AWS_REGION', 'us-east-1'))
s3_client = boto3.client('s3', region_name=os.environ.get('AWS_REGION', 'us-east-1'))

# MSK producer (optional)
kafka_producer = None
if MSK_BOOTSTRAP:
    try:
        from aws_msk_iam_sasl_signer import MSKAuthTokenProvider
        from kafka import KafkaProducer
        import ssl

        def msk_token_provider(config):
            token, _ = MSKAuthTokenProvider.generate_auth_token(os.environ.get('AWS_REGION', 'us-east-1'))
            return token

        kafka_producer = KafkaProducer(
            bootstrap_servers=MSK_BOOTSTRAP,
            security_protocol='SASL_SSL',
            sasl_mechanism='OAUTHBEARER',
            sasl_oauth_token_provider=type('', (), {'token': staticmethod(msk_token_provider)})(),
            ssl_context=ssl.create_default_context(),
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        )
        logger.info(f"MSK producer connected to {MSK_BOOTSTRAP}")
    except Exception as e:
        logger.warning(f"MSK producer setup failed: {e}")


@app.route('/health')
@app.route('/')
def health():
    return jsonify({"status": "ok", "service": SERVICE_NAME, "platform": "ecs"})


@app.route('/order', methods=['GET', 'POST'])
def create_order():
    order_id = str(uuid.uuid4())
    steps = []

    # DynamoDB
    try:
        table = dynamodb.Table(TABLE_NAME)
        table.put_item(Item={
            'orderId': order_id, 'status': 'CREATED',
            'timestamp': str(int(time.time())), 'platform': 'ecs'
        })
        steps.append("dynamodb: order written")
    except Exception as e:
        steps.append(f"dynamodb: error - {e}")

    # S3
    if BUCKET_NAME:
        try:
            s3_client.get_object(Bucket=BUCKET_NAME, Key='catalog.json')
            steps.append("s3: catalog read")
        except Exception as e:
            steps.append(f"s3: {e}")

    # Lambda via API Gateway
    if PAYMENT_URL:
        try:
            resp = requests.post(PAYMENT_URL, json={
                "order_id": order_id, "amount": 42.99, "currency": "USD"
            }, timeout=10)
            steps.append(f"payment: {resp.json()}")
        except Exception as e:
            steps.append(f"payment: error - {e}")

    # Inventory via ALB
    if INVENTORY_URL:
        try:
            resp = requests.get(f"{INVENTORY_URL}/inventory?product_id=OLJCESPC7Z", timeout=10)
            steps.append(f"inventory: {resp.json()}")
        except Exception as e:
            steps.append(f"inventory: error - {e}")

    # MSK publish
    if kafka_producer:
        try:
            with tracer.start_as_current_span("msk.publish", attributes={
                "messaging.system": "kafka", "messaging.operation": "publish",
                "messaging.destination": "otel-demo-orders"
            }):
                kafka_producer.send('otel-demo-orders', {
                    'orderId': order_id, 'status': 'CREATED', 'platform': 'ecs'
                })
                kafka_producer.flush(timeout=5)
                steps.append("msk: order event published")
        except Exception as e:
            steps.append(f"msk: error - {e}")

    return jsonify({"orderId": order_id, "platform": "ecs", "steps": steps})


if __name__ == '__main__':
    port = int(os.environ.get('SERVICE_PORT', '8080'))
    logger.info(f"Order processor starting on :{port}")
    app.run(host='0.0.0.0', port=port)
