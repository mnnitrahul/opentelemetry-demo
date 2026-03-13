"""Multi-Platform Caller - EKS Service with vanilla OTel auto-instrumentation.
Periodically calls ECS, Lambda, and EC2 services. Trace propagation handled
by opentelemetry-instrument via OTEL_PROPAGATORS env var."""
import os, time, logging, requests
from opentelemetry import trace

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SERVICE_NAME = os.environ.get('OTEL_SERVICE_NAME', 'multi-platform-caller')
ECS_URL = os.environ.get('ECS_ORDER_URL', '')
LAMBDA_URL = os.environ.get('LAMBDA_PAYMENT_URL', '')
EC2_URL = os.environ.get('EC2_INVENTORY_URL', '')

tracer = trace.get_tracer(__name__)


def call_services():
    with tracer.start_as_current_span("call-all-platforms") as span:
        span.set_attribute("caller.iteration", True)

        if ECS_URL:
            try:
                resp = requests.get(ECS_URL, timeout=20)
                logger.info(f"ECS: {resp.status_code}")
            except Exception as e:
                logger.error(f"ECS: {e}")

        if LAMBDA_URL:
            try:
                resp = requests.post(LAMBDA_URL,
                    json={"order_id": "caller", "amount": 9.99},
                    timeout=15)
                logger.info(f"Lambda: {resp.status_code}")
            except Exception as e:
                logger.error(f"Lambda: {e}")

        if EC2_URL:
            try:
                resp = requests.get(EC2_URL, timeout=15)
                logger.info(f"EC2: {resp.status_code}")
            except Exception as e:
                logger.error(f"EC2: {e}")


if __name__ == '__main__':
    logger.info(f"Starting caller: ECS={ECS_URL} Lambda={LAMBDA_URL} EC2={EC2_URL}")
    while True:
        try:
            call_services()
        except Exception as e:
            logger.error(f"Error: {e}")
        time.sleep(30)
