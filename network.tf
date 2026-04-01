data "aws_availability_zones" "available" {
  state = "available"
}

# Only AZs that offer the selected GPU instance type — prevents node group
# creation failures in zones where sparse SKUs (p4d, p5) are unavailable.
data "aws_ec2_instance_type_offerings" "gpu" {
  filter {
    name   = "instance-type"
    values = [var.gpu_instance_type]
  }
  location_type = "availability-zone"
}

locals {
  # Intersect GPU-capable AZs with the region's available AZs, then sort for
  # deterministic ordering across plan runs.
  valid_gpu_azs = sort(setintersection(
    toset(data.aws_ec2_instance_type_offerings.gpu.locations),
    toset(data.aws_availability_zones.available.names),
  ))
}

resource "terraform_data" "gpu_az_validation" {
  lifecycle {
    precondition {
      condition     = length(local.valid_gpu_azs) >= 2
      error_message = "The selected region does not have >= 2 availability zones offering ${var.gpu_instance_type}. Choose a different region or instance type."
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6"

  name = "sie-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(local.valid_gpu_azs, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = false
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.project_name}" = "shared"
    "kubernetes.io/role/elb"    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.project_name}"       = "shared"
    "kubernetes.io/role/internal-elb" = "1"
  }
}
