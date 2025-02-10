terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.aws_region
}

# ACM Certificate
resource "aws_acm_certificate" "api" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation record
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.hosted_zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# API Gateway
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = var.environment
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip            = "$context.identity.sourceIp"
      requestTime   = "$context.requestTime"
      httpMethod    = "$context.httpMethod"
      routeKey      = "$context.routeKey"
      status        = "$context.status"
      protocol      = "$context.protocol"
      responseTime  = "$context.responseLatency"
      integrationError = "$context.integrationErrorMessage"
    })
  }
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/api-gateway/${var.project_name}"
  retention_in_days = 30
}

# Generate requirements.txt
resource "local_file" "requirements" {
  content = join("\n", [for name, version in var.lambda_dependencies : "${name}${version}"])
  filename = "${path.module}/lambda/requirements.txt"
}

# Install dependencies in a Docker container
resource "null_resource" "install_dependencies" {
  triggers = {
    dependencies_hash = sha256(local_file.requirements.content)
  }

  provisioner "local-exec" {
    command = <<EOF
      docker run --rm -v /Users/ekolp/workspace/becausefuckyouthatswhy-back-end/lambda:/lambda -w /lambda public.ecr.aws/sam/build-python3.13:latest \
      pip install -r requirements.txt -t .
    EOF
  }

  depends_on = [local_file.requirements]
}

# Lambda Function
resource "aws_lambda_function" "main" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "${var.project_name}-function"
  role            = aws_iam_role.lambda_role.arn
  handler         = "app.lambda_handler"
  runtime         = "python3.13"
  timeout         = 30
  memory_size     = 128

  environment {
    variables = {
      POWERTOOLS_SERVICE_NAME = var.project_name
      LOG_LEVEL              = "INFO"
    }
  }
}

# Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "lambda"
  output_path = "lambda.zip"
  depends_on  = [null_resource.install_dependencies]
}

# API Gateway Integration
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.main.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "any" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*/{proxy+}"
}
