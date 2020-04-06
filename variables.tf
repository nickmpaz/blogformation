data "aws_route53_zone" "external" {
  name = "blogformation.net"
}

variable "region" {
  default = "us-east-1"
}

variable "www_domain_name" {
  default = "www.blogformation.net"
}

variable "root_domain_name" {
  default = "blogformation.net"
}
