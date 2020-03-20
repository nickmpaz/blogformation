provider "aws" {
  region = "us-east-1"
}

data "aws_route53_zone" "external" {
  name = "blogformation.net"
}

# variable "www_domain_name" {
#   default = "www.blogformation.net"
# }

# variable "root_domain_name" {
#   default = "blogformation.net"
# }

variable "bucket_name" {
  default = "blogformation"
}



resource "aws_s3_bucket" "b" {
  bucket = var.bucket_name
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
      "Resource":["arn:aws:s3:::${var.bucket_name}/*"]
    }
  ]
}
POLICY
  website {
    index_document = "index.html"
  }
}

resource "aws_s3_bucket_object" "f" {
  bucket       = aws_s3_bucket.b.id
  key          = "index.html"
  source       = "site/index.html"
  content_type = "text/html"
  etag         = filemd5("site/index.html")
}

resource "aws_acm_certificate" "default" {
  domain_name       = "blogformation.net"
  validation_method = "DNS"
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

resource "aws_cloudfront_distribution" "cloudfront" {
  origin {
    domain_name = aws_s3_bucket.b.bucket_regional_domain_name
    origin_id   = var.bucket_name
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = ["blogformation.net"]

  default_cache_behavior {
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    // This needs to match the `origin_id` above.
    target_origin_id = var.bucket_name
    min_ttl          = 0
    default_ttl      = 86400
    max_ttl          = 31536000

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
  name    = "blogformation.net"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.cloudfront.domain_name
    zone_id                = aws_cloudfront_distribution.cloudfront.hosted_zone_id
    evaluate_target_health = false
  }
}