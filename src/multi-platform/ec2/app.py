"""Inventory Service - ECS Service with vanilla OTel auto-instrumentation."""
import json, os, logging
import boto3, redis
from flask import Flask, request, jsonify
from opentelemetry import trace

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SERVICE_NAME = os.environ.get('OTEL_SERVICE_NAME', 'multi-inventory-service')
VALKEY_ADDR = os.environ.get('VALKEY_ADDR', '')
BUCKET_NAME = os.environ.get('S3_BUCKET_NAME', '')

tracer = trace.get_tracer(__name__)

app = Flask(__name__)

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
    return jsonify({"status": "ok", "service": SERVICE_NAME, "platform": "ecs"})

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

    return jsonify({"productId": product_id, "platform": "ecs", "steps": steps})

if __name__ == '__main__':
    port = int(os.environ.get('SERVICE_PORT', '8080'))
    logger.info(f"Inventory service starting on :{port}")
    app.run(host='0.0.0.0', port=port)
