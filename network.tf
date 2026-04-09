data "aws_availability_zones" "available" {
  state = "available"
}

# AZ offerings per GPU instance type — prevents node group creation failures
# in zones where sparse SKUs (p4d, p5, g7e) are unavailable.
data "aws_ec2_instance_type_offerings" "gpu" {
  for_each = toset(local.gpu_instance_types)

  filter {
    name   = "instance-type"
    values = [each.value]
  }
  location_type = "availability-zone"
}

locals {
  # Effective GPU groups: multi-GPU list if set, else single group from legacy vars
  effective_gpu_groups = length(var.gpu_node_groups) > 0 ? var.gpu_node_groups : [{
    name          = "gpu"
    instance_type = var.gpu_instance_type
    capacity_type = var.gpu_capacity_type
    min_size      = var.gpu_min_size
    max_size      = var.gpu_max_size
    labels        = {}
  }]

  gpu_instance_types = distinct([for g in local.effective_gpu_groups : g.instance_type])

  # Per-instance-type: sorted list of AZs that offer the type
  gpu_azs_by_type = {
    for type in local.gpu_instance_types :
    type => sort(tolist(setintersection(
      toset(data.aws_ec2_instance_type_offerings.gpu[type].locations),
      toset(data.aws_availability_zones.available.names),
    )))
  }

  # Union of all GPU-capable AZs — VPC spans these so every node group has
  # at least one subnet it can use.
  all_gpu_azs = sort(tolist(setunion([
    for azs in values(local.gpu_azs_by_type) : toset(azs)
  ]...)))

  # Cap at 3 AZs for cost (NAT gateway per AZ).
  # AZs are sorted alphabetically — if some GPU types only exist in later AZs,
  # they may get fewer subnets. gpu_group_subnets filters per group below.
  vpc_azs = slice(local.all_gpu_azs, 0, min(3, length(local.all_gpu_azs)))

  # Dynamic CIDR blocks based on AZ count
  private_subnets = [for i in range(length(local.vpc_azs)) : cidrsubnet("10.0.0.0/16", 8, i + 1)]
  public_subnets  = [for i in range(length(local.vpc_azs)) : cidrsubnet("10.0.0.0/16", 8, i + 101)]

  # Map AZ → private subnet ID (for per-node-group subnet filtering)
  az_to_private_subnet = zipmap(local.vpc_azs, module.vpc.private_subnets)

  # Per GPU group: only subnets in AZs where the instance type is available
  gpu_group_subnets = {
    for g in local.effective_gpu_groups :
    g.name => [
      for az in local.vpc_azs :
      local.az_to_private_subnet[az]
      if contains(local.gpu_azs_by_type[g.instance_type], az)
    ]
  }

  # Pre-check: ensure every GPU group has at least one AZ within the VPC
  gpu_groups_without_coverage = [
    for g in local.effective_gpu_groups : g.name
    if length(setintersection(toset(local.vpc_azs), toset(local.gpu_azs_by_type[g.instance_type]))) == 0
  ]
}

resource "terraform_data" "gpu_az_validation" {
  for_each = toset(local.gpu_instance_types)

  lifecycle {
    precondition {
      condition     = length(local.gpu_azs_by_type[each.key]) >= 1
      error_message = "No availability zone in the selected region offers ${each.key}. Choose a different region or instance type."
    }
  }
}

resource "terraform_data" "gpu_subnet_coverage_validation" {
  lifecycle {
    precondition {
      condition     = length(local.gpu_groups_without_coverage) == 0
      error_message = "GPU node groups [${join(", ", local.gpu_groups_without_coverage)}] have no VPC subnets in their available AZs. The VPC spans ${join(", ", local.vpc_azs)} but these GPU types need different AZs. Reduce the number of GPU types or increase the AZ cap."
    }
  }
}

resource "terraform_data" "vpc_az_validation" {
  lifecycle {
    precondition {
      condition     = length(local.all_gpu_azs) >= 1
      error_message = "The selected region has no availability zones offering the requested GPU instance types. Choose a different region."
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6"

  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = local.vpc_azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = false
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.project_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.project_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}
