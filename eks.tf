# KMS Key for EKS Secrets Encryption

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_policy_document" "eks_kms" {
  # Allow account root full KMS access (required default for key management)
  statement {
    sid    = "AllowRootFullAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Allow the Terraform caller to manage grants and use the key for EKS encryption
  statement {
    sid    = "AllowTerraformCallerKeyUsage"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.arn]
    }
    actions = [
      "kms:DescribeKey",
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "eks_secrets" {
  description             = "KMS key for EKS cluster secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.eks_kms.json

  tags = {
    Name = "${var.project_name}-eks-secrets"
  }
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.project_name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15.1"

  name               = var.project_name
  kubernetes_version = "1.35"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_private_access                      = true
  endpoint_public_access                       = true          # TODO: Disable for production or restrict CIDRs
  endpoint_public_access_cidrs                 = ["0.0.0.0/0"] # TODO: Restrict to corporate IPs in production
  node_security_group_enable_recommended_rules = true

  # Grants admin access to whoever runs terraform apply
  enable_cluster_creator_admin_permissions = true

  # Cluster encryption - encrypt secrets at rest
  encryption_config = {
    provider_key_arn = aws_kms_key.eks_secrets.arn
    resources        = ["secrets"]
  }

  # Cluster logging - enable all log types for audit and debugging
  enabled_log_types = ["audit", "api", "authenticator", "controllerManager", "scheduler"]

  # Essential EKS add-ons for node health
  # before_compute = true installs addons BEFORE node groups
  addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent    = true
      before_compute = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.arn
    }
  }

  timeouts = {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  eks_managed_node_groups = merge(
    {
      cpu = {
        min_size       = 1
        max_size       = 5
        instance_types = ["t3.xlarge"]            # 4 vCPU, 16GB
        ami_type       = "AL2023_x86_64_STANDARD" # Amazon Linux 2023

        iam_role_additional_policies = {
          AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        }

        timeouts = {
          create = "90m"
          update = "90m"
          delete = "90m"
        }
      }
    },
    {
      for g in local.effective_gpu_groups :
      g.name => {
        min_size       = g.min_size
        max_size       = g.max_size
        instance_types = [g.instance_type]
        ami_type       = "AL2023_x86_64_NVIDIA"
        capacity_type  = g.capacity_type
        subnet_ids     = local.gpu_group_subnets[g.name]

        # 100GB root volume — large CUDA images need >20GB default
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = 100
              volume_type           = "gp3"
              delete_on_termination = true
            }
          }
        }

        labels = merge(
          {
            "environment"                   = "test"
            "managed-by"                    = "terraform"
            "sie.superlinked.com/node-type" = "gpu"
          },
          g.labels,
        )

        iam_role_additional_policies = {
          AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        }

        taints = {
          gpu = {
            key    = "nvidia.com/gpu"
            value  = "present"
            effect = "NO_SCHEDULE"
          }
        }

        tags = {
          "k8s.io/cluster-autoscaler/enabled"             = "true"
          "k8s.io/cluster-autoscaler/${var.project_name}" = "owned"
        }

        timeouts = {
          create = "90m"
          update = "90m"
          delete = "90m"
        }
      }
    }
  )
}

resource "aws_security_group_rule" "eks_egress_to_vpc_endpoints" {
  security_group_id        = module.eks.cluster_security_group_id
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vpc_endpoint.id
  description              = "Allow EKS control plane to communicate with VPC endpoints"
}
