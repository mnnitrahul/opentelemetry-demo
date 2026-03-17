"""Multi-Platform Caller - EKS Service with vanilla OTel auto-instrumentation.
Periodically calls ECS, Lambda, and EC2 services. Trace propagation handled
by opentelemetry-instrument via OTEL_PROPAGATORS env var.
Every 10th iteration (~5 min), calls /order-slow endpoints to simulate
slow PostgreSQL queries on Aurora."""
import os, time, logging, requests
from opentelemetry import trace

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SERVICE_NAME = os.environ.get('OTEL_SERVICE_NAME', 'multi-platform-caller')
ECS_URL = os.environ.get('ECS_ORDER_URL', '')
JAVA_URL = os.environ.get('ECS_ORDER_JAVA_URL', '')
LAMBDA_URL = os.environ.get('LAMBDA_PAYMENT_URL', '')
EC2_URL = os.environ.get('EC2_INVENTORY_URL', '')

tracer = trace.get_tracer(__name__)
iteration = 0


def call_services():
    global iteration
    iteration += 1
    slow = (iteration % 10 == 0)

    with tracer.start_as_current_span("call-all-platforms") as span:
        span.set_attribute("caller.iteration", iteration)
        span.set_attribute("caller.slow_query", slow)

        # ECS Python order-processor
        if ECS_URL:
            url = ECS_URL.replace("/order", "/order-slow") if slow else ECS_URL
            try:
                resp = requests.get(url, timeout=30 if slow else 20)
                logger.info(f"ECS{'(slow)' if slow else ''}: {resp.status_code}")
            except Exception as e:
                logger.error(f"ECS: {e}")

        # ECS Java order-processor
        if JAVA_URL:
            url = JAVA_URL.replace("/order-java", "/order-java-slow") if slow else JAVA_URL
            try:
                resp = requests.get(url, timeout=30 if slow else 20)
                logger.info(f"Java{'(slow)' if slow else ''}: {resp.status_code}")
            except Exception as e:
                logger.error(f"Java: {e}")

        # Lambda via API Gateway
        if LAMBDA_URL:
            try:
                resp = requests.post(LAMBDA_URL,
                    json={"order_id": f"caller-{iteration}", "amount": 9.99},
                    timeout=15)
                logger.info(f"Lambda: {resp.status_code}")
            except Exception as e:
                logger.error(f"Lambda: {e}")

        # Inventory via ALB
        if EC2_URL:
            try:
                resp = requests.get(EC2_URL, timeout=15)
                logger.info(f"Inventory: {resp.status_code}")
            except Exception as e:
                logger.error(f"Inventory: {e}")


if __name__ == '__main__':
    logger.info(f"Starting caller: ECS={ECS_URL} Java={JAVA_URL} Lambda={LAMBDA_URL} EC2={EC2_URL}")
    while True:
        try:
            call_services()
        except Exception as e:
            logger.error(f"Error: {e}")
        time.sleep(30)
