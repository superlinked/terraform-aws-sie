# SIE EKS Cluster — Development Example (G6 Spot)
#
# Creates an EKS cluster with g6.2xlarge spot GPU nodes (NVIDIA L4),
# scale-to-zero (min=0), and up to 5 GPU nodes.
# Terraform = cloud infra only. K8s resources deployed via Helm:
#
#   $(terraform output -raw kubectl_config_command)
#   # Populate the model cache bucket (only if create_model_cache=true):
#   sie-admin cache populate --bundle default \
#     --target $(terraform output -raw model_cache_bucket_url)/
#   helm upgrade --install sie-cluster oci://ghcr.io/superlinked/charts/sie-cluster --version 0.6.0 \
#     --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(terraform output -raw sie_irsa_role_arn) \
#     $(terraform output -raw model_cache_helm_args)
#   # No extra --set is required for the payload store: the chart auto-derives
#   # payloadStore.url to "<clusterCache.url>/payloads" and the terraform
#   # module grants the workload IRSA role RW access on the /payloads/ prefix.
#   # Override only if you want a separate bucket: --set payloadStore.url=s3://other-bucket/prefix
#
# Prerequisites:
#   1. AWS credentials configured (aws configure or environment variables)
#   2. EC2 quota for g6.2xlarge in the target region
#   3. SIE Docker images pushed to ECR (mise run cluster create --provider aws --name dev-g6-spot)
#
# Usage:
#   cd deploy/terraform/aws/examples/dev-g6-spot
#   terraform init
#   terraform plan
#   terraform apply
#
# Cleanup:
#   terraform destroy

terraform {
  required_version = ">= 1.14"

  # Uncomment to use S3 remote state (run deploy/terraform/aws/bootstrap first)
  # backend "s3" {
  #   bucket = "sie-terraform-state-<suffix>"
  #   key    = "sie/eks-dev-g6-spot"
  #   region = "eu-central-1"
  # }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "sie-dev"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = "sie"
      Cluster = var.project_name
    }
  }
}

module "sie_eks" {
  source  = "superlinked/sie/aws"
  version = "0.6.0"

  aws_region        = var.aws_region
  project_name      = var.project_name
  gpu_instance_type = "g6.2xlarge"
  gpu_capacity_type = "SPOT"
  gpu_min_size      = 0
  gpu_max_size      = 5

  create_model_cache = true # creates an S3 bucket; remove or set to false to skip
  # creates account-scoped ECR repos (sie-dev/sie-server etc.); remove or set false to skip
  create_ecr_repositories = true
}

# =============================================================================
# Outputs
# =============================================================================

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.sie_eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.sie_eks.cluster_endpoint
  sensitive   = true
}

output "kubectl_config_command" {
  description = "Run this to configure kubectl"
  value       = module.sie_eks.kubectl_config_command
}

output "sie_irsa_role_arn" {
  description = "IRSA role ARN — pass to helm install"
  value       = module.sie_eks.sie_irsa_role_arn
}

output "cluster_autoscaler_irsa_role_arn" {
  description = "Cluster autoscaler IRSA role ARN — pass to helm install"
  value       = module.sie_eks.cluster_autoscaler_irsa_role_arn
}

output "ecr_server_repository_url" {
  description = "ECR repository URL for sie-server images"
  value       = module.sie_eks.ecr_server_repository_url
}

output "ecr_gateway_repository_url" {
  description = "ECR repository URL for sie-gateway images"
  value       = module.sie_eks.ecr_gateway_repository_url
}

output "ecr_config_repository_url" {
  description = "ECR repository URL for sie-config images"
  value       = module.sie_eks.ecr_config_repository_url
}

output "workload_identity_annotation" {
  description = "Helm --set value for IRSA role-ARN annotation"
  value       = "eks.amazonaws.com/role-arn=${module.sie_eks.sie_irsa_role_arn}"
}

output "model_cache_bucket_url" {
  description = "S3 URL — pass to Helm as workers.common.clusterCache.url"
  value       = module.sie_eks.model_cache_bucket_url
}

output "model_cache_helm_args" {
  description = "Helm --set arguments to enable the cluster cache"
  value       = "--set workers.common.clusterCache.enabled=true --set workers.common.clusterCache.url=${module.sie_eks.model_cache_bucket_url}"
}
