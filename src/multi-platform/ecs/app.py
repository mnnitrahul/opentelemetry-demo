"""Order Processor - ECS Service with OTel SDK + collector sidecar."""
import json, os, uuid, time, logging, boto3, requests
from flask import Flask, request, jsonify
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.instrumentation.botocore import BotocoreInstrumentor
from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
from opentelemetry.instrumentation.kafka import KafkaInstrumentor

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SERVICE_NAME = os.environ.get('OTEL_SERVICE_NAME', 'multi-order-processor')
TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', 'otel-demo-orders')
BUCKET_NAME = os.environ.get('S3_BUCKET_NAME', '')
PAYMENT_URL = os.environ.get('PAYMENT_PROCESSOR_URL', '')
INVENTORY_URL = os.environ.get('INVENTORY_SERVICE_URL', '')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
SQS_QUEUE_URL = os.environ.get('SQS_QUEUE_URL', '')
KINESIS_STREAM = os.environ.get('KINESIS_STREAM_NAME', '')
REGION = os.environ.get('AWS_REGION', 'us-east-1')

# Aurora PostgreSQL
PG_HOST = os.environ.get('PG_HOST', '')
PG_PORT = os.environ.get('PG_PORT', '5432')
PG_USER = os.environ.get('PG_USER', 'otelu')
PG_PASSWORD = os.environ.get('PG_PASSWORD', 'otelpassword123')
PG_DATABASE = os.environ.get('PG_DATABASE', 'otel')

# MSK Serverless (Kafka with IAM auth)
MSK_BOOTSTRAP = os.environ.get('MSK_BOOTSTRAP', '')

resource = Resource.create({"service.name": SERVICE_NAME, "service.namespace": "otel-demo-multi"})
provider = TracerProvider(resource=resource)
exporter = OTLPSpanExporter(endpoint="http://localhost:4318/v1/traces")
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(SERVICE_NAME)

BotocoreInstrumentor().instrument()
RequestsInstrumentor().instrument()
Psycopg2Instrumentor().instrument()
KafkaInstrumentor().instrument()

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

dynamodb = boto3.resource('dynamodb', region_name=REGION)
sns = boto3.client('sns', region_name=REGION)
sqs = boto3.client('sqs', region_name=REGION)
kinesis = boto3.client('kinesis', region_name=REGION)
s3_client = boto3.client('s3', region_name=REGION)

# Aurora PostgreSQL connection
pg_conn = None
if PG_HOST:
    try:
        import psycopg2
        pg_conn = psycopg2.connect(
            host=PG_HOST, port=int(PG_PORT),
            user=PG_USER, password=PG_PASSWORD,
            dbname=PG_DATABASE, sslmode='require',
            connect_timeout=5
        )
        pg_conn.autocommit = True
        with pg_conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS orders (
                    order_id VARCHAR(255) PRIMARY KEY,
                    status VARCHAR(50),
                    platform VARCHAR(50),
                    created_at TIMESTAMP DEFAULT NOW()
                )
            """)
        logger.info(f"Aurora PostgreSQL connected: {PG_HOST}")
    except Exception as e:
        logger.warning(f"Aurora PostgreSQL setup failed: {e}")
        pg_conn = None

# MSK Kafka producer (IAM auth)
kafka_producer = None
if MSK_BOOTSTRAP:
    try:
        from kafka import KafkaProducer
        from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

        class MSKTokenProvider:
            def token(self):
                token, _ = MSKAuthTokenProvider.generate_auth_token(REGION)
                return token

        tp = MSKTokenProvider()
        kafka_producer = KafkaProducer(
            bootstrap_servers=MSK_BOOTSTRAP,
            security_protocol='SASL_SSL',
            sasl_mechanism='OAUTHBEARER',
            sasl_oauth_token_provider=tp,
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            request_timeout_ms=10000,
            api_version_auto_timeout_ms=10000,
        )
        logger.info(f"MSK Kafka connected: {MSK_BOOTSTRAP}")
    except Exception as e:
        logger.warning(f"MSK Kafka setup failed: {e}")
        kafka_producer = None

@app.route('/health')
@app.route('/')
def health():
    return jsonify({"status": "ok", "service": SERVICE_NAME, "platform": "ecs"})

@app.route('/order', methods=['GET', 'POST'])
def create_order():
    order_id = str(uuid.uuid4())
    order_data = {"orderId": order_id, "status": "CREATED", "platform": "ecs", "timestamp": str(int(time.time()))}
    steps = []

    # DynamoDB
    try:
        dynamodb.Table(TABLE_NAME).put_item(Item=order_data)
        steps.append("dynamodb: order written")
    except Exception as e:
        steps.append(f"dynamodb: {e}")

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
            resp = requests.post(PAYMENT_URL, json={"order_id": order_id, "amount": 42.99}, timeout=10)
            steps.append(f"payment: {resp.status_code}")
        except Exception as e:
            steps.append(f"payment: {e}")

    # Inventory via ALB
    if INVENTORY_URL:
        try:
            resp = requests.get(f"{INVENTORY_URL}/inventory?product_id=OLJCESPC7Z", timeout=10)
            steps.append(f"inventory: {resp.status_code}")
        except Exception as e:
            steps.append(f"inventory: {e}")

    # SNS
    if SNS_TOPIC_ARN:
        try:
            sns.publish(TopicArn=SNS_TOPIC_ARN, Message=json.dumps(order_data), Subject="OrderCreated")
            steps.append("sns: published")
        except Exception as e:
            steps.append(f"sns: {e}")

    # SQS (direct, separate from SNS subscription)
    if SQS_QUEUE_URL:
        try:
            sqs.send_message(QueueUrl=SQS_QUEUE_URL, MessageBody=json.dumps(order_data))
            steps.append("sqs: sent")
        except Exception as e:
            steps.append(f"sqs: {e}")

    # Kinesis
    if KINESIS_STREAM:
        try:
            kinesis.put_record(StreamName=KINESIS_STREAM, Data=json.dumps(order_data).encode(), PartitionKey=order_id)
            steps.append("kinesis: put record")
        except Exception as e:
            steps.append(f"kinesis: {e}")

    # Aurora PostgreSQL
    if pg_conn:
        try:
            with pg_conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO orders (order_id, status, platform) VALUES (%s, %s, %s) ON CONFLICT (order_id) DO NOTHING",
                    (order_id, "CREATED", "ecs")
                )
            steps.append("aurora: order inserted")
        except Exception as e:
            steps.append(f"aurora: {e}")

    # MSK Kafka
    if kafka_producer:
        try:
            kafka_producer.send('otel-demo-orders', value=order_data)
            kafka_producer.flush(timeout=5)
            steps.append("msk: message sent")
        except Exception as e:
            steps.append(f"msk: {e}")

    return jsonify({"orderId": order_id, "platform": "ecs", "steps": steps})

if __name__ == '__main__':
    port = int(os.environ.get('SERVICE_PORT', '8080'))
    logger.info(f"Order processor starting on :{port}")
    app.run(host='0.0.0.0', port=port)
