"""
Order Processor - ECS Service
Uses vanilla OpenTelemetry SDK. Sends OTLP to OTel Collector (via NLB).
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
from opentelemetry.propagate import set_global_textmap
from opentelemetry.propagators.aws import AwsXRayPropagator

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SERVICE_NAME = os.environ.get('OTEL_SERVICE_NAME', 'multi-order-processor')
TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', 'otel-demo-orders')
BUCKET_NAME = os.environ.get('S3_BUCKET_NAME', '')
PAYMENT_URL = os.environ.get('PAYMENT_PROCESSOR_URL', '')
INVENTORY_URL = os.environ.get('INVENTORY_SERVICE_URL', '')

# Set up OpenTelemetry with OTLP exporter
resource = Resource.create({
    "service.name": SERVICE_NAME,
    "service.namespace": "otel-demo-multi"
})
provider = TracerProvider(resource=resource)
otlp_endpoint = os.environ.get('OTEL_EXPORTER_OTLP_ENDPOINT', '')
if otlp_endpoint:
    exporter = OTLPSpanExporter(endpoint=otlp_endpoint)
    provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

# Use AWS X-Ray propagator for trace context across API Gateway
set_global_textmap(AwsXRayPropagator())

tracer = trace.get_tracer(SERVICE_NAME)

# Auto-instrument libraries
BotocoreInstrumentor().instrument()
RequestsInstrumentor().instrument()

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

dynamodb = boto3.resource('dynamodb', region_name=os.environ.get('AWS_REGION', 'us-east-1'))
s3_client = boto3.client('s3', region_name=os.environ.get('AWS_REGION', 'us-east-1'))


@app.route('/health')
@app.route('/')
def health():
    return jsonify({"status": "ok", "service": SERVICE_NAME, "platform": "ecs"})


@app.route('/order', methods=['GET', 'POST'])
def create_order():
    order_id = str(uuid.uuid4())
    steps = []

    # Step 1: Write order to DynamoDB
    try:
        table = dynamodb.Table(TABLE_NAME)
        table.put_item(Item={
            'orderId': order_id,
            'status': 'CREATED',
            'timestamp': str(int(time.time())),
            'platform': 'ecs'
        })
        steps.append("dynamodb: order written")
    except Exception as e:
        steps.append(f"dynamodb: error - {e}")

    # Step 2: Read from S3
    if BUCKET_NAME:
        try:
            s3_client.get_object(Bucket=BUCKET_NAME, Key='catalog.json')
            steps.append("s3: catalog read")
        except Exception as e:
            steps.append(f"s3: {e}")

    # Step 3: Call Lambda payment processor via API Gateway
    if PAYMENT_URL:
        try:
            resp = requests.post(PAYMENT_URL, json={
                "order_id": order_id, "amount": 42.99, "currency": "USD"
            }, timeout=10)
            steps.append(f"payment: {resp.json()}")
        except Exception as e:
            steps.append(f"payment: error - {e}")

    # Step 4: Call EC2 inventory service via ALB
    if INVENTORY_URL:
        try:
            resp = requests.get(
                f"{INVENTORY_URL}/inventory?product_id=OLJCESPC7Z", timeout=10)
            steps.append(f"inventory: {resp.json()}")
        except Exception as e:
            steps.append(f"inventory: error - {e}")

    return jsonify({"orderId": order_id, "platform": "ecs", "steps": steps})


if __name__ == '__main__':
    port = int(os.environ.get('SERVICE_PORT', '8080'))
    logger.info(f"Order processor starting on :{port}")
    app.run(host='0.0.0.0', port=port)
