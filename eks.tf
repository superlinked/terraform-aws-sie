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

locals {
  kubelet_log_retention_node_config = [
    {
      content_type = "application/node.eks.aws"
      content      = <<-EOT
        ---
        apiVersion: node.eks.aws/v1alpha1
        kind: NodeConfig
        spec:
          kubelet:
            config:
              containerLogMaxSize: ${var.kubelet_container_log_max_size}
              containerLogMaxFiles: ${var.kubelet_container_log_max_files}
      EOT
    }
  ]

  # Default the observability node group's AMI to the AL2023 family matching the
  # instance architecture, so a Graviton/ARM `instance_type` never pairs with an
  # x86_64 AMI (or vice versa). Consumers can still override `ami_type`.
  observability_ami_type = coalesce(
    var.observability_node_group.ami_type,
    try(contains(data.aws_ec2_instance_type.observability[0].supported_architectures, "arm64"), false) ? "AL2023_ARM_64_STANDARD" : "AL2023_x86_64_STANDARD",
  )
}

# Resolves the observability instance's architecture (only queried when the group
# is enabled) so `local.observability_ami_type` can pick a matching AL2023 AMI.
data "aws_ec2_instance_type" "observability" {
  count         = var.observability_node_group.enabled ? 1 : 0
  instance_type = var.observability_node_group.instance_type
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

  # Essential EKS add-ons for node health.
  # `before_compute = true` installs the addon before node groups
  # come up. `resolve_conflicts_on_*` = OVERWRITE so an addon being
  # recreated from a tainted state takes ownership of the existing
  # in-cluster resources (e.g. ebs-csi-controller-sa annotations)
  # instead of erroring with ConfigurationConflict.
  addons = {
    vpc-cni = {
      most_recent                 = true
      before_compute              = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    coredns = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    kube-proxy = {
      most_recent                 = true
      before_compute              = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    aws-ebs-csi-driver = {
      most_recent                 = true
      service_account_role_arn    = module.ebs_csi_irsa.arn
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
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

        # 100GB root volume — obs stack + EKS addons exceed 20GB default
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

        cloudinit_pre_nodeadm = local.kubelet_log_retention_node_config

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
        min_size = g.min_size
        max_size = g.max_size
        # Seed desired_size from min_size so node groups with min_size >= 2 don't
        # fail validation (EKS requires min_size <= desired_size <= max_size, and
        # the upstream module defaults desired_size to 1). Clamp to >=1 so pools
        # that scale to zero (min_size=0) still match the historical default of
        # one warm node at create time; the cluster autoscaler manages
        # desired_size after creation via ignore_changes.
        desired_size   = max(g.min_size, 1)
        instance_types = [g.instance_type]
        ami_type       = "AL2023_x86_64_NVIDIA"
        capacity_type  = g.capacity_type
        subnet_ids     = local.gpu_group_subnets[g.name]

        # GPU root volume. Large CUDA/SGLang images plus model caches need
        # substantially more than the EKS default, and size is configurable per
        # node group for parity with the GCP Terraform module.
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = g.disk_size_gb
              volume_type           = g.disk_type
              delete_on_termination = true
            }
          }
        }

        cloudinit_pre_nodeadm = local.kubelet_log_retention_node_config

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
          # Node-template hints — without these, cluster-autoscaler
          # doesn't know that nodes from this ASG will carry the
          # `sie.superlinked.com/node-type=gpu` label and the
          # `nvidia.com/gpu=present:NoSchedule` taint, so it refuses
          # to scale up for GPU pods (logs "cannot put pod on any
          # node" / no TriggerScaleUp event). EKS managed nodegroups
          # apply labels/taints via kubelet args at boot but DON'T
          # auto-mirror them into the ASG tags that CA reads at
          # simulation time. See cluster-autoscaler/cloudprovider/aws
          # README, "Auto-Discovery Setup".
          "k8s.io/cluster-autoscaler/node-template/label/sie.superlinked.com/node-type" = "gpu"
          "k8s.io/cluster-autoscaler/node-template/taint/nvidia.com/gpu"                = "present:NoSchedule"
        }

        timeouts = {
          create = "90m"
          update = "90m"
          delete = "90m"
        }
      }
    },
    var.observability_node_group.enabled ? {
      observability = {
        min_size = var.observability_node_group.min_size
        max_size = var.observability_node_group.max_size
        # Seed desired from min so create-time validation passes; the cluster
        # autoscaler manages desired_size after creation via ignore_changes.
        desired_size   = max(var.observability_node_group.min_size, 1)
        instance_types = [var.observability_node_group.instance_type]
        ami_type       = local.observability_ami_type

        # Single subnet => single-AZ ASG, so the AZ-locked observability EBS
        # volumes (Prometheus/Loki/Grafana) always have a node to bind to. A
        # multi-AZ group can leave their AZ nodeless after a roll and orphan the
        # pods. Steer obs pods here with a nodeSelector on
        # `sie.superlinked.com/node-type=observability` (see Helm values).
        subnet_ids = [
          local.az_to_private_subnet[coalesce(var.observability_node_group.availability_zone, local.vpc_azs[0])]
        ]

        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = var.observability_node_group.disk_size_gb
              volume_type           = var.observability_node_group.disk_type
              delete_on_termination = true
            }
          }
        }

        cloudinit_pre_nodeadm = local.kubelet_log_retention_node_config

        labels = {
          "managed-by"                    = "terraform"
          "sie.superlinked.com/node-type" = "observability"
        }

        # Dedicate this node group to observability so nothing else consumes the
        # reserved capacity (Prometheus needs its burst headroom). The critical
        # DaemonSets (aws-node, kube-proxy, ebs-csi-node, node-exporter, alloy)
        # all tolerate NoSchedule via operator:Exists, so volumes still mount and
        # the node stays monitored; obs pods carry a matching toleration (see
        # values-tester-cluster.yaml).
        taints = {
          dedicated = {
            key    = "sie.superlinked.com/node-type"
            value  = "observability"
            effect = "NO_SCHEDULE"
          }
        }

        iam_role_additional_policies = {
          AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        }

        tags = {
          "k8s.io/cluster-autoscaler/enabled"                                           = "true"
          "k8s.io/cluster-autoscaler/${var.project_name}"                               = "owned"
          "k8s.io/cluster-autoscaler/node-template/label/sie.superlinked.com/node-type" = "observability"
          "k8s.io/cluster-autoscaler/node-template/taint/sie.superlinked.com/node-type" = "observability:NoSchedule"
        }

        timeouts = {
          create = "90m"
          update = "90m"
          delete = "90m"
        }
      }
    } : {}
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
