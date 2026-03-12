"""
Multi-Platform Caller - EKS Service
Periodically calls ECS, Lambda, and EC2 services with OTel trace propagation.
"""
import os
import time
import logging
import requests

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.propagate import set_global_textmap
from opentelemetry.propagators.composite import CompositePropagator
from opentelemetry.trace.propagation import TraceContextTextMapPropagator
from opentelemetry.baggage.propagation import W3CBaggagePropagator

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SERVICE_NAME = os.environ.get('OTEL_SERVICE_NAME', 'multi-platform-caller')
ECS_URL = os.environ.get('ECS_ORDER_URL', '')
LAMBDA_URL = os.environ.get('LAMBDA_PAYMENT_URL', '')
EC2_URL = os.environ.get('EC2_INVENTORY_URL', '')

resource = Resource.create({
    "service.name": SERVICE_NAME,
    "service.namespace": "otel-demo-multi"
})
provider = TracerProvider(resource=resource)
otlp_endpoint = os.environ.get('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://otel-collector:4317')
exporter = OTLPSpanExporter(endpoint=otlp_endpoint)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
set_global_textmap(CompositePropagator([TraceContextTextMapPropagator(), W3CBaggagePropagator()]))
tracer = trace.get_tracer(SERVICE_NAME)

RequestsInstrumentor().instrument()


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
