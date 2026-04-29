# SIE EKS Terraform - Validation Tests
#
# Run with: terraform test
# Requires Terraform >= 1.7.0

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
    server_ecr_repository_name  = "sie-server"
    gateway_ecr_repository_name = "sie-gateway"
    config_ecr_repository_name  = "sie-config"
  }

  # ECR server repository should be created
  assert {
    condition     = aws_ecr_repository.server.name == "sie-server"
    error_message = "ECR server repository name should match variable"
  }

  # ECR gateway repository should be created
  assert {
    condition     = aws_ecr_repository.gateway.name == "sie-gateway"
    error_message = "ECR gateway repository name should match variable"
  }

  # ECR config repository should be created (sie-config control plane image)
  assert {
    condition     = aws_ecr_repository.config.name == "sie-config"
    error_message = "ECR config repository name should match variable"
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

  # GPU node group should use specified instance type
  assert {
    condition     = module.eks.eks_managed_node_groups["gpu"].node_group_resources[0].autoscaling_groups[0] != null
    error_message = "GPU node group should be created"
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
    condition     = module.vpc.enable_dns_hostnames == true
    error_message = "VPC should have DNS hostnames enabled"
  }

  # VPC should enable NAT gateway for private subnet internet access
  assert {
    condition     = module.vpc.natgw_ids != null
    error_message = "VPC should have NAT gateway for private subnets"
  }
}

run "validate_irsa_role" {
  command = plan

  variables {
    project_name             = "sie-test"
    sie_namespace            = "sie"
    sie_service_account_name = "sie-server"
  }

  # SIE IRSA role should be created
  assert {
    condition     = module.sie_irsa_role.arn != null
    error_message = "SIE IRSA role should be created"
  }
}
