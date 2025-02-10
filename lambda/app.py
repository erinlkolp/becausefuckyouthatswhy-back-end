from aws_lambda_powertools import Logger, Tracer, Metrics
from aws_lambda_powertools.event_handler.api_gateway import ApiGatewayResolver, ProxyEventType
from aws_lambda_powertools.logging import correlation_paths
from aws_lambda_powertools.metrics import MetricUnit
import json

logger = Logger()
tracer = Tracer()
metrics = Metrics(namespace="MyApplication")
app = ApiGatewayResolver(proxy_type=ProxyEventType.APIGatewayProxyEventV2)

@app.get("/hello")
@tracer.capture_method
def hello():
    metrics.add_metric(name="HelloWorldInvocations", unit=MetricUnit.Count, value=1)
    logger.info("Hello world endpoint called")
    response = {"message": "Hello World!"}
    return json.dumps(response, indent=4)

@app.get("/hello/<name>")
@tracer.capture_method
def hello_name(name):
    metrics.add_metric(name="HelloNameInvocations", unit=MetricUnit.Count, value=1)
    logger.info(f"Hello {name} endpoint called")
    return {"message": f"Hello {name}!"}

@logger.inject_lambda_context(correlation_id_path=correlation_paths.API_GATEWAY_REST)
@tracer.capture_lambda_handler
@metrics.log_metrics(capture_cold_start_metric=True)
def lambda_handler(event, context):
    return app.resolve(event, context)
