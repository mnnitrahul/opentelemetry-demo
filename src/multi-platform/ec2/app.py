"""
Inventory Service - EC2/ASG Service
Uses AWS X-Ray SDK for tracing (auto-signs with instance IAM role).
"""
import json
import os
import logging

import boto3
import redis
from flask import Flask, request, jsonify
from aws_xray_sdk.core import xray_recorder, patch_all
from aws_xray_sdk.ext.flask.middleware import XRayMiddleware

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SERVICE_NAME = os.environ.get('OTEL_SERVICE_NAME', 'multi-inventory-service')
VALKEY_ADDR = os.environ.get('VALKEY_ADDR', '')
BUCKET_NAME = os.environ.get('S3_BUCKET_NAME', '')

# Configure X-Ray
xray_recorder.configure(service=SERVICE_NAME)
patch_all()

app = Flask(__name__)
XRayMiddleware(app, xray_recorder)

s3_client = boto3.client('s3', region_name=os.environ.get('AWS_REGION', 'us-east-1'))
redis_client = None
if VALKEY_ADDR:
    try:
        host, port = VALKEY_ADDR.rsplit(':', 1)
        redis_client = redis.Redis(host=host, port=int(port), ssl=True, decode_responses=True,
                                   socket_connect_timeout=5)
    except Exception as e:
        logger.warning(f"Redis connection setup failed: {e}")


@app.route('/health')
@app.route('/')
def health():
    return jsonify({"status": "ok", "service": SERVICE_NAME, "platform": "ec2"})


@app.route('/inventory')
def get_inventory():
    product_id = request.args.get('product_id', 'OLJCESPC7Z')
    steps = []

    # Step 1: Check Redis cache
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

    # Step 2: Read from S3
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
