"""Pricing Service - EC2 ASG Service with OTel auto-instrumentation.

Provides product pricing lookups with DynamoDB storage and S3 catalog reads.
Designed to run behind an ALB on an Auto Scaling Group.
"""
import json, os, logging, time
from decimal import Decimal
import boto3
from flask import Flask, request, jsonify
from opentelemetry import trace

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SERVICE_NAME = os.environ.get('OTEL_SERVICE_NAME', 'multi-pricing-service')
TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', 'otel-demo-pricing')
BUCKET_NAME = os.environ.get('S3_BUCKET_NAME', '')
REGION = os.environ.get('AWS_REGION', 'us-east-1')

tracer = trace.get_tracer(__name__)
app = Flask(__name__)
app.json.sort_keys = False


class DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, Decimal):
            return float(o)
        return super().default(o)


app.json_encoder = DecimalEncoder

dynamodb = boto3.resource('dynamodb', region_name=REGION)
s3_client = boto3.client('s3', region_name=REGION)

# Seed pricing data on startup
SEED_PRICES = {
    "OLJCESPC7Z": {"name": "Sunglasses", "price": Decimal("19.99"), "currency": "USD"},
    "66VCHSJNUP": {"name": "Tank Top", "price": Decimal("18.99"), "currency": "USD"},
    "1YMWWN1N4O": {"name": "Watch", "price": Decimal("109.99"), "currency": "USD"},
    "L9ECAV7KIM": {"name": "Loafers", "price": Decimal("89.99"), "currency": "USD"},
    "2ZYFJ3GM2N": {"name": "Hairdryer", "price": Decimal("24.99"), "currency": "USD"},
}


def seed_pricing_table():
    """Seed DynamoDB table with sample pricing data."""
    try:
        table = dynamodb.Table(TABLE_NAME)
        for product_id, info in SEED_PRICES.items():
            table.put_item(Item={"productId": product_id, **info})
        logger.info(f"Seeded {len(SEED_PRICES)} items into {TABLE_NAME}")
    except Exception as e:
        logger.warning(f"Could not seed pricing table: {e}")


@app.route('/health')
@app.route('/')
def health():
    return jsonify({"status": "ok", "service": SERVICE_NAME, "platform": "ec2-asg"})


@app.route('/price', methods=['GET'])
def get_price():
    """Look up price for a product by ID."""
    product_id = request.args.get('product_id', 'OLJCESPC7Z')
    steps = []

    # Read from DynamoDB
    try:
        table = dynamodb.Table(TABLE_NAME)
        resp = table.get_item(Key={"productId": product_id})
        item = resp.get('Item')
        if item:
            steps.append(f"dynamodb: found {item['name']} @ {float(item['price'])} {item['currency']}")
        else:
            steps.append("dynamodb: product not found")
    except Exception as e:
        steps.append(f"dynamodb: {e}")

    # Read catalog from S3
    if BUCKET_NAME:
        try:
            s3_client.get_object(Bucket=BUCKET_NAME, Key='catalog.json')
            steps.append("s3: catalog loaded")
        except Exception as e:
            steps.append(f"s3: {e}")

    return jsonify({"productId": product_id, "platform": "ec2-asg", "steps": steps})


@app.route('/prices', methods=['GET'])
def list_prices():
    """List all product prices."""
    steps = []
    items = []

    try:
        table = dynamodb.Table(TABLE_NAME)
        resp = table.scan()
        items = resp.get('Items', [])
        steps.append(f"dynamodb: scanned {len(items)} items")
    except Exception as e:
        steps.append(f"dynamodb: {e}")

    return jsonify({"products": items, "platform": "ec2-asg", "steps": steps})


if __name__ == '__main__':
    seed_pricing_table()
    port = int(os.environ.get('SERVICE_PORT', '8080'))
    logger.info(f"Pricing service starting on :{port}")
    app.run(host='0.0.0.0', port=port)
