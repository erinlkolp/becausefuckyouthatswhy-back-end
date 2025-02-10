variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "domain_name" {
  description = "Domain name for the API Gateway"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "lambda_dependencies" {
  description = "Map of Python dependencies and their versions"
  type        = map(string)
  default = {
    "aws-lambda-powertools[all]" = ">=2.0.0"
  }
}
