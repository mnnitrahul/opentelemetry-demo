"""
Inventory Service - EC2/ASG Service
Uses vanilla OpenTelemetry SDK. Sends OTLP to OTel Collector (via NLB).
"""
import json
import os
import logging

import boto3
import redis
from flask import Flask, request, jsonify
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.botocore import BotocoreInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SERVICE_NAME = os.environ.get('OTEL_SERVICE_NAME', 'multi-inventory-service')
VALKEY_ADDR = os.environ.get('VALKEY_ADDR', '')
BUCKET_NAME = os.environ.get('S3_BUCKET_NAME', '')

# Set up OpenTelemetry with OTLP exporter
resource = Resource.create({
    "service.name": SERVICE_NAME,
    "service.namespace": "otel-demo-multi"
})
provider = TracerProvider(resource=resource)
otlp_endpoint = os.environ.get('OTEL_EXPORTER_OTLP_ENDPOINT', '')
if otlp_endpoint:
    exporter = OTLPSpanExporter(endpoint=f"{otlp_endpoint}/v1/traces")
    provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(SERVICE_NAME)

# Auto-instrument libraries
BotocoreInstrumentor().instrument()
RedisInstrumentor().instrument()

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

s3_client = boto3.client('s3', region_name=os.environ.get('AWS_REGION', 'us-east-1'))
redis_client = None
if VALKEY_ADDR:
    try:
        host, port = VALKEY_ADDR.rsplit(':', 1)
        redis_client = redis.Redis(
            host=host, port=int(port), ssl=True,
            decode_responses=True, socket_connect_timeout=5)
    except Exception as e:
        logger.warning(f"Redis setup failed: {e}")


@app.route('/health')
@app.route('/')
def health():
    return jsonify({"status": "ok", "service": SERVICE_NAME, "platform": "ec2"})


@app.route('/inventory')
def get_inventory():
    product_id = request.args.get('product_id', 'OLJCESPC7Z')
    steps = []

    if redis_client:
        try:
            cached = redis_client.get(f"inventory:{product_id}")
            if cached:
                steps.append(f"redis: cache hit - {cached}")
            else:
                steps.append("redis: cache miss")
                redis_client.setex(f"inventory:{product_id}", 300, "42")
                steps.append("redis: cached quantity=42")
        except Exception as e:
            steps.append(f"redis: error - {e}")

    if BUCKET_NAME:
        try:
            s3_client.get_object(Bucket=BUCKET_NAME, Key='catalog.json')
            steps.append("s3: catalog loaded")
        except Exception as e:
            steps.append(f"s3: {e}")

    return jsonify({"productId": product_id, "platform": "ec2", "steps": steps})


if __name__ == '__main__':
    port = int(os.environ.get('SERVICE_PORT', '8080'))
    logger.info(f"Inventory service starting on :{port}")
    app.run(host='0.0.0.0', port=port)
