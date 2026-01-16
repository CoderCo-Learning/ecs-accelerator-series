# ## normal way - once SCF region is same as ALB region etc...

# data "aws_route53_zone" "main" {
#   name = "lab.moabukar.co.uk"
# }

# data "aws_lbs" "all" {}

# locals {
#   scfdemo_alb = [
#     for lb_arn in data.aws_lbs.all.arns :
#     lb_arn if length(regexall("alb-scfdemo-dev", lb_arn)) > 0
#   ][0]
# }

# data "aws_lb" "scfdemo" {
#   arn = local.scfdemo_alb
# }

# resource "aws_route53_record" "api" {
#   zone_id = data.aws_route53_zone.main.zone_id
#   name    = "api.lab.moabukar.co.uk"
#   type    = "A"

#   alias {
#     name                   = data.aws_lb.scfdemo.dns_name
#     zone_id                = data.aws_lb.scfdemo.zone_id
#     evaluate_target_health = false
#   }
# }

### hacky way - when i deployed SCF to us-east-1 region, it created the ALB in us-east-1 region but the ALB is in eu-west-2 region
### so i had to create a provider for us-east-1 region to get the ALB

data "aws_route53_zone" "main" {
  name = "lab.moabukar.co.uk"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_lbs" "all" {
  provider = aws.us_east_1
}

locals {
  scfdemo_alb = [
    for lb_arn in data.aws_lbs.all.arns :
    lb_arn if length(regexall("alb-scfdemo-dev", lb_arn)) > 0
  ][0]
}

data "aws_lb" "scfdemo" {
  provider = aws.us_east_1
  arn      = local.scfdemo_alb
}

resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.lab.moabukar.co.uk"
  type    = "A"

  alias {
    name                   = data.aws_lb.scfdemo.dns_name
    zone_id                = data.aws_lb.scfdemo.zone_id
    evaluate_target_health = false
  }
}


## old working

# data "aws_route53_zone" "main" {
#   name = "lab.moabukar.co.uk"
# }

# resource "aws_route53_record" "api" {
#   zone_id = data.aws_route53_zone.main.zone_id
#   name    = "api.lab.moabukar.co.uk"
#   type    = "A"

#   alias {
#     name                   = "dualstack.alb-scfdemo-dev-308822729.us-east-1.elb.amazonaws.com"
#     zone_id                = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
#     evaluate_target_health = false
#   }
# }