# SIE EKS Terraform - Validation Tests
#
# Run with: terraform -chdir=deploy/terraform/aws/infra test
# Requires Terraform >= 1.7.0

provider "aws" {
  region = "eu-central-1"
}

# =============================================================================
# Variable Validation Tests (plan-only, no infrastructure)
# =============================================================================

run "validate_cluster_name" {
  command = plan

  variables {
    project_name = "sie-test"
  }

  # EKS cluster name should match project_name
  assert {
    condition     = module.eks.cluster_name == "sie-test"
    error_message = "EKS cluster name should match project_name variable"
  }
}

run "validate_ecr_repositories" {
  command = plan

  variables {
    project_name                = "sie-test"
    create_ecr_repositories     = true
    server_ecr_repository_name  = "sie-server"
    gateway_ecr_repository_name = "sie-gateway"
    config_ecr_repository_name  = "sie-config"
  }

  # ECR server repository should be created with project_name prefix
  assert {
    condition     = aws_ecr_repository.server[0].name == "sie-test/sie-server"
    error_message = "ECR server repository name should be prefixed with project_name"
  }

  # ECR gateway repository should be created with project_name prefix
  assert {
    condition     = aws_ecr_repository.gateway[0].name == "sie-test/sie-gateway"
    error_message = "ECR gateway repository name should be prefixed with project_name"
  }

  # ECR config repository should be created with project_name prefix
  assert {
    condition     = aws_ecr_repository.config[0].name == "sie-test/sie-config"
    error_message = "ECR config repository name should be prefixed with project_name"
  }
}

run "validate_gpu_node_group_spot" {
  command = plan

  variables {
    project_name      = "sie-test"
    gpu_instance_type = "g6.xlarge"
    gpu_capacity_type = "SPOT"
    gpu_min_size      = 0
    gpu_max_size      = 5
  }

  # GPU node group should be wired from the plan-known GPU config.
  assert {
    condition = (
      contains(keys(module.eks.eks_managed_node_groups), "gpu")
      && try(local.effective_gpu_groups[0].instance_type, null) == "g6.xlarge"
      && try(local.effective_gpu_groups[0].capacity_type, null) == "SPOT"
      && try(local.effective_gpu_groups[0].min_size, null) == 0
      && try(local.effective_gpu_groups[0].max_size, null) == 5
    )

    error_message = "GPU node group should be planned with the requested instance type, capacity type, and scaling bounds"
  }
}

run "validate_kms_encryption" {
  command = plan

  variables {
    project_name = "sie-test"
  }

  # KMS key for EKS secrets should be created
  assert {
    condition     = aws_kms_alias.eks_secrets.name == "alias/sie-test-eks-secrets"
    error_message = "KMS alias should follow naming convention: alias/{project_name}-eks-secrets"
  }
}

run "validate_vpc_configuration" {
  command = plan

  variables {
    project_name = "sie-test"
  }

  # VPC should enable DNS hostnames
  assert {
    condition     = module.vpc.vpc_enable_dns_hostnames == true
    error_message = "VPC should have DNS hostnames enabled"
  }

  # VPC should enable NAT gateway for private subnet internet access
  assert {
    condition     = module.vpc.natgw_ids != null
    error_message = "VPC should have NAT gateway for private subnets"
  }

  # Private worker subnets should be large enough for EKS VPC CNI pod IPs.
  assert {
    condition     = alltrue([for cidr in local.private_subnets : tonumber(split("/", cidr)[1]) == 20])
    error_message = "Private subnets should default to /20 for EKS pod IP headroom"
  }

  # Public subnets only need room for load balancers/NAT and should not consume
  # the larger worker subnet space.
  assert {
    condition     = alltrue([for cidr in local.public_subnets : tonumber(split("/", cidr)[1]) == 24])
    error_message = "Public subnets should default to /24"
  }

  # Keep default public subnets on the historical 10.0.101.0/24 range where
  # possible so existing load balancer/NAT subnets do not churn unnecessarily.
  assert {
    condition     = local.public_subnets == [for i in range(length(local.vpc_azs)) : cidrsubnet(var.vpc_cidr, local.public_subnet_newbits, 101 + i)]
    error_message = "Default public subnets should preserve the legacy 10.0.101.0/24-style allocation"
  }
}

run "validate_irsa_role" {
  command = plan

  variables {
    project_name             = "sie-test"
    sie_namespace            = "sie"
    sie_service_account_name = "sie-server"
  }

  # IRSA-adjacent workload policy should be planned with the expected name.
  # The IAM role ARN/name from the upstream module is only known after apply.
  assert {
    condition     = aws_iam_role_policy.sie_ecr_access.name == "sie-test-ecr-access"
    error_message = "SIE workload ECR policy should follow naming convention: {project_name}-ecr-access"
  }
}
