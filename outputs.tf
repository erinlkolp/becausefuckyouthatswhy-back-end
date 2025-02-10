# API Gateway Domain Configuration
resource "aws_apigatewayv2_domain_name" "api" {
  domain_name = var.domain_name

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.api.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  depends_on = [aws_acm_certificate_validation.api]
}

# API Gateway Domain Mapping
resource "aws_apigatewayv2_api_mapping" "api" {
  api_id      = aws_apigatewayv2_api.main.id
  domain_name = aws_apigatewayv2_domain_name.api.id
  stage       = aws_apigatewayv2_stage.main.id
}

# Route53 record for the API Gateway domain
resource "aws_route53_record" "api" {
  name    = var.domain_name
  type    = "A"
  zone_id = var.hosted_zone_id

  alias {
    name                   = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
    zone_id               = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

output "api_endpoint" {
  description = "API Gateway endpoint URLs"
  value = {
    default_url = "${aws_apigatewayv2_api.main.api_endpoint}/${aws_apigatewayv2_stage.main.name}"
    custom_domain = "https://${var.domain_name}"
  }
}