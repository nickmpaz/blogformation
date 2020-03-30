provider "aws" {
  region = "us-east-1"
}

data "aws_route53_zone" "external" {
  name = "blogformation.net"
}

variable "www_domain_name" {
  default = "www.blogformation.net"
}

variable "root_domain_name" {
  default = "blogformation.net"
}

resource "aws_s3_bucket" "www" {
  bucket = var.www_domain_name
  acl    = "public-read"
  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"AddPermissions",
      "Effect":"Allow",
      "Principal": "*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::${var.www_domain_name}/*"]
    }
  ]
}
POLICY
  website {
    index_document = "index.html"
  }
}

resource "aws_s3_bucket_object" "index" {
  bucket       = aws_s3_bucket.www.id
  key          = "index.html"
  source       = "site/index.html"
  content_type = "text/html"
  etag         = filemd5("site/index.html")
}

resource "aws_acm_certificate" "default" {
  domain_name               = "*.${var.root_domain_name}"
  subject_alternative_names = [var.root_domain_name]
  validation_method         = "DNS"
}

resource "aws_route53_record" "validation" {
  name    = aws_acm_certificate.default.domain_validation_options.0.resource_record_name
  type    = aws_acm_certificate.default.domain_validation_options.0.resource_record_type
  zone_id = data.aws_route53_zone.external.zone_id
  records = ["${aws_acm_certificate.default.domain_validation_options.0.resource_record_value}"]
  ttl     = "60"
}

resource "aws_acm_certificate_validation" "default" {
  certificate_arn = aws_acm_certificate.default.arn
  validation_record_fqdns = [
    "${aws_route53_record.validation.fqdn}",
  ]
}

resource "aws_cloudfront_distribution" "www_distribution" {
  origin {
    domain_name = aws_s3_bucket.www.bucket_regional_domain_name
    origin_id   = var.www_domain_name
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.www_domain_name, var.root_domain_name]

  default_cache_behavior {
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = var.www_domain_name
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.default.certificate_arn
    minimum_protocol_version = "TLSv1"
    ssl_support_method       = "sni-only"
  }
}

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.external.zone_id
  name    = var.www_domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.www_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.www_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "root" {
  zone_id = data.aws_route53_zone.external.zone_id
  name    = var.root_domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.www_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.www_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}




resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_lambda_function" "test_lambda" {
  filename      = "lambda/lambda_function_payload.zip"
  function_name = "test_lambda"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "handler.my_handler"  # code entrypoint
  source_code_hash = filebase64sha256("lambda/lambda_function_payload.zip")
  runtime = "python3.8"
  depends_on = [aws_iam_role_policy_attachment.lambda_logs, aws_cloudwatch_log_group.example]
}

# This is to optionally manage the CloudWatch Log Group for the Lambda Function.
# If skipping this resource configuration, also add "logs:CreateLogGroup" to the IAM policy below.
resource "aws_cloudwatch_log_group" "example" {
  name              = "/aws/lambda/test_lambda" ## FIXME USE A VARIABLE FOR LAMBDA FUNCTION NAME SO YOU DONT HAVE TO HARD CODE THIS AND SO YOU DONT CREATE A DEPENDENCY CYCLE
  retention_in_days = 14
}

# See also the following AWS managed policy: AWSLambdaBasicExecutionRole
resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

# resource "aws_apigatewayv2_api" "gateway" {
#   name                       = "example-websocket`-api"
#   protocol_type              = "WEBSOCKET"
#   route_selection_expression = "$request.body.action"
# }



resource "aws_cloudformation_stack" "cs" {
  name = "websocket-stack"
  parameters = {
    MyLambdaFunction = aws_lambda_function.test_lambda.arn
    MyLambdaFunctionURI = aws_lambda_function.test_lambda.invoke_arn
  }
  template_body = file("./template.json")
  
  capabilities = ["CAPABILITY_AUTO_EXPAND"]
}
