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
          local.ecr_server_repository_arn,
          local.ecr_gateway_repository_arn,
          local.ecr_config_repository_arn
        ]
      }
    ]
  })
}

# Inline policy for read-only access to the model cache bucket.
# Created only when var.create_model_cache is true.
resource "aws_iam_role_policy" "sie_model_cache_ro" {
  count = var.create_model_cache ? 1 : 0

  name = "${var.project_name}-model-cache-ro"
  role = module.sie_irsa_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "ListModelCache"
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = module.model_cache_bucket[0].s3_bucket_arn
        },
        {
          Sid      = "ReadModelCache"
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = "${module.model_cache_bucket[0].s3_bucket_arn}/*"
        }
      ],
      local.normalized_model_cache_kms_key_id == null ? [] : [
        {
          Sid      = "DecryptModelCacheObjects"
          Effect   = "Allow"
          Action   = ["kms:Decrypt", "kms:DescribeKey"]
          Resource = local.normalized_model_cache_kms_key_id
        }
      ]
    )
  })
}

# Inline policy granting RW access to the /payloads/ prefix of the model
# cache bucket. The gateway offloads work items larger than 1MB there and
# workers fetch them back; without this grant any request >1MB silently
# fails with "all_items_failed" at the worker. Scoped to /payloads/* and
# guarded by an s3:prefix condition on ListBucket so it cannot read or
# write model weights.
resource "aws_iam_role_policy" "sie_payload_store_rw" {
  count = var.create_model_cache ? 1 : 0

  name = "${var.project_name}-payload-store-rw"
  role = module.sie_irsa_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "ListPayloadStorePrefix"
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = module.model_cache_bucket[0].s3_bucket_arn
          Condition = {
            StringLike = {
              "s3:prefix" = ["payloads/*"]
            }
          }
        },
        {
          Sid    = "ReadWritePayloadObjects"
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject",
            "s3:AbortMultipartUpload",
          ]
          Resource = "${module.model_cache_bucket[0].s3_bucket_arn}/payloads/*"
        },
      ],
      local.normalized_model_cache_kms_key_id == null ? [] : [
        {
          Sid      = "EncryptDecryptPayloadObjects"
          Effect   = "Allow"
          Action   = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"]
          Resource = local.normalized_model_cache_kms_key_id
        }
      ]
    )
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
