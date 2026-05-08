locals {
  # Compose the URL/ARN strings from inputs rather than reading them
  # off the resource attribute. The ECR resources below are
  # `count`-gated; downstream modules (irsa.tf, outputs.tf) need
  # these strings whether the repos are created here or pre-exist.
  # Format matches what AWS returns.
  ecr_repository_url_prefix = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  ecr_arn_prefix            = "arn:${data.aws_partition.current.partition}:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository"

  ecr_server_repository_url  = "${local.ecr_repository_url_prefix}/${var.server_ecr_repository_name}"
  ecr_gateway_repository_url = "${local.ecr_repository_url_prefix}/${var.gateway_ecr_repository_name}"
  ecr_config_repository_url  = "${local.ecr_repository_url_prefix}/${var.config_ecr_repository_name}"

  ecr_server_repository_arn  = "${local.ecr_arn_prefix}/${var.server_ecr_repository_name}"
  ecr_gateway_repository_arn = "${local.ecr_arn_prefix}/${var.gateway_ecr_repository_name}"
  ecr_config_repository_arn  = "${local.ecr_arn_prefix}/${var.config_ecr_repository_name}"
}

resource "aws_ecr_repository" "server" {
  count                = var.create_ecr_repositories ? 1 : 0
  name                 = var.server_ecr_repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "gateway" {
  count                = var.create_ecr_repositories ? 1 : 0
  name                 = var.gateway_ecr_repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "config" {
  count                = var.create_ecr_repositories ? 1 : 0
  name                 = var.config_ecr_repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}
