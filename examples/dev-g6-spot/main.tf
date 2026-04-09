# SIE EKS Cluster — Development Example (G6 Spot)
#
# Creates an EKS cluster with g6.xlarge spot GPU nodes (NVIDIA L4),
# scale-to-zero (min=0), and up to 5 GPU nodes.
# Terraform = cloud infra only. K8s resources deployed via Helm:
#
#   $(terraform output -raw kubectl_config_command)
#   helm upgrade --install sie-cluster oci://ghcr.io/superlinked/charts/sie-cluster --version 0.1.10 \
#     --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(terraform output -raw sie_irsa_role_arn)
#
# Prerequisites:
#   1. AWS credentials configured (aws configure or environment variables)
#   2. EC2 quota for g6.xlarge in the target region
#   3. SIE Docker images pushed to ECR (docker push to ECR)
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
  required_version = "~> 1.14.3"

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
}

module "sie_eks" {
  source  = "superlinked/sie/aws"
  version = "0.1.10"

  aws_region        = var.aws_region
  project_name      = var.project_name
  gpu_instance_type = "g6.xlarge"
  gpu_capacity_type = "SPOT"
  gpu_min_size      = 0
  gpu_max_size      = 5
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
