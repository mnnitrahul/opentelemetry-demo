"""Multi-Platform Caller - EKS Service with vanilla OTel auto-instrumentation.
Each service call creates its own independent trace for granular analysis."""
import os, time, logging, requests
from opentelemetry import trace, context

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SERVICE_NAME = os.environ.get('OTEL_SERVICE_NAME', 'multi-platform-caller')
ECS_URL = os.environ.get('ECS_ORDER_URL', '')
JAVA_URL = os.environ.get('ECS_ORDER_JAVA_URL', '')
VERTX_URL = os.environ.get('ECS_ORDER_VERTX_URL', '')
LAMBDA_URL = os.environ.get('LAMBDA_PAYMENT_URL', '')
EC2_URL = os.environ.get('EC2_INVENTORY_URL', '')
EC2_PRICING_URL = os.environ.get('EC2_PRICING_URL', '')

tracer = trace.get_tracer(__name__)
iteration = 0


def call(name, method, url, **kwargs):
    """Make an HTTP call in its own root trace."""
    # Start a fresh root context (no parent) so each call is a separate trace
    token = context.attach(context.set_value("_", None))
    try:
        with tracer.start_as_current_span(f"call-{name}") as span:
            span.set_attribute("caller.target", name)
            try:
                if method == "GET":
                    resp = requests.get(url, **kwargs)
                else:
                    resp = requests.post(url, **kwargs)
                logger.info(f"{name}: {resp.status_code}")
            except Exception as e:
                logger.error(f"{name}: {e}")
    finally:
        context.detach(token)


def run_cycle():
    global iteration
    iteration += 1
    slow = (iteration % 10 == 0)

    # ECS Python order-processor
    if ECS_URL:
        url = ECS_URL.replace("/order", "/order-slow") if slow else ECS_URL
        call(f"ecs-python{'(slow)' if slow else ''}", "GET", url, timeout=30 if slow else 20)

    # ECS Java order-processor
    if JAVA_URL:
        url = JAVA_URL.replace("/order-java", "/order-java-slow") if slow else JAVA_URL
        call(f"ecs-java{'(slow)' if slow else ''}", "GET", url, timeout=30 if slow else 20)

    # ECS Vert.x order-processor
    if VERTX_URL:
        if slow:
            vurl = VERTX_URL.replace("/order-vertx", "/order-vertx-slow")
        elif iteration % 3 == 0:
            vurl = VERTX_URL.replace("/order-vertx", "/order-vertx-rx-db")
        elif iteration % 3 == 1:
            vurl = VERTX_URL.replace("/order-vertx", "/order-vertx-native-db")
        else:
            vurl = VERTX_URL
        call(f"ecs-vertx({vurl.split('/')[-1]})", "GET", vurl, timeout=30 if slow else 20)

    # Lambda via API Gateway
    if LAMBDA_URL:
        call("lambda-payment", "POST", LAMBDA_URL,
             json={"order_id": f"caller-{iteration}", "amount": 9.99}, timeout=15)

    # Inventory via ALB
    if EC2_URL:
        call("ecs-inventory", "GET", EC2_URL, timeout=15)

    # Pricing via EC2 ASG ALB
    if EC2_PRICING_URL:
        call("ec2-asg-pricing", "GET", EC2_PRICING_URL, timeout=15)


if __name__ == '__main__':
    logger.info(f"Starting caller: ECS={ECS_URL} Java={JAVA_URL} Vertx={VERTX_URL} Lambda={LAMBDA_URL} EC2={EC2_URL} Pricing={EC2_PRICING_URL}")
    while True:
        try:
            run_cycle()
        except Exception as e:
            logger.error(f"Error: {e}")
        time.sleep(30)
