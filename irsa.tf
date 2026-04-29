# IRSA (IAM Roles for Service Accounts) Configuration
#
# Equivalent to GCP Workload Identity - allows K8s pods to assume IAM roles
# without storing credentials.

# IAM Role for SIE Workloads
module "sie_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.4.0"

  name = "${var.project_name}-workload-role"

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.sie_namespace}:${var.sie_service_account_name}"]
    }
  }

  tags = {
    Purpose = "SIE workload identity"
  }
}

# Inline policy for ECR access
resource "aws_iam_role_policy" "sie_ecr_access" {
  name = "${var.project_name}-ecr-access"
  role = module.sie_irsa_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRGetAuthorizationToken"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPullImages"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = [
          aws_ecr_repository.server.arn,
          aws_ecr_repository.gateway.arn,
          aws_ecr_repository.config.arn
        ]
      }
    ]
  })
}

# IAM Role for EBS CSI Driver
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.4.0"

  name = "${var.project_name}-ebs-csi"

  attach_ebs_csi_policy = true

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

output "sie_irsa_role_arn" {
  description = "ARN of the IAM role for SIE workloads (use in Helm values)"
  value       = module.sie_irsa_role.arn
}
