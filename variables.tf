variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "The general project name for resource naming."
  type        = string
  default     = "sie"
}

variable "server_ecr_repository_name" {
  description = "The name of the ECR repository for the sie-server."
  type        = string
  default     = "sie-server"
}

variable "gateway_ecr_repository_name" {
  description = "The name of the ECR repository for the sie-gateway."
  type        = string
  default     = "sie-gateway"
}

variable "config_ecr_repository_name" {
  description = "The name of the ECR repository for the sie-config control plane image."
  type        = string
  default     = "sie-config"
}

# When false, the module skips `aws_ecr_repository` resource creation
# but still emits the ecr_*_repository_url / _arn outputs (composed
# from caller identity + the repo-name variables). Set false on
# accounts where the ECR repos are managed by another stack so a
# fresh `terraform apply` doesn't trip on
# RepositoryAlreadyExistsException, and `terraform destroy` doesn't
# delete repos other clusters depend on. IRSA + helm wiring is
# unchanged either way.
variable "create_ecr_repositories" {
  description = "Whether this module manages the ECR repositories. Default `false` — matches the chart's GHCR-by-default behaviour and avoids `RepositoryAlreadyExistsException` on accounts where the repos already exist. Set `true` to opt in to terraform-managed ECR. The `ecr_*_repository_url` outputs are emitted either way (composed from caller identity + repo names) so IRSA / Helm wiring works regardless of who creates the repos."
  type        = bool
  default     = false
}

variable "ecr_repository_prefix" {
  description = "Namespace prefix for ECR repository names — final names become \"<prefix>/<repo_name>\". When null (default), prefix is var.project_name so two engineers using project_name=sie-dev-laszlo and project_name=sie-dev-bob don't collide. Set to empty string \"\" to disable the prefix (use bare names — needed when ECR repos are managed externally with bare names, e.g. sie-perf-lab phase 04)."
  type        = string
  default     = null
}

# =============================================================================
# Networking
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the EKS VPC. Existing clusters will replace networking resources if this changes."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_prefix_length" {
  description = "CIDR prefix length for private worker subnets. Default /20 gives EKS pod IP headroom for bursty GPU node scale-ups."
  type        = number
  default     = 20

  validation {
    condition     = floor(var.private_subnet_prefix_length) == var.private_subnet_prefix_length && var.private_subnet_prefix_length >= 18 && var.private_subnet_prefix_length <= 22
    error_message = "private_subnet_prefix_length must be an integer between 18 and 22."
  }
}

variable "public_subnet_prefix_length" {
  description = "CIDR prefix length for public load balancer/NAT subnets. Default /24 keeps public subnet allocation compact."
  type        = number
  default     = 24

  validation {
    condition     = floor(var.public_subnet_prefix_length) == var.public_subnet_prefix_length && var.public_subnet_prefix_length >= 20 && var.public_subnet_prefix_length <= 28
    error_message = "public_subnet_prefix_length must be an integer between 20 and 28."
  }
}

# =============================================================================
# SIE Application Configuration
# =============================================================================

variable "sie_namespace" {
  description = "Kubernetes namespace where SIE workloads run"
  type        = string
  default     = "sie"
}

variable "sie_service_account_name" {
  description = "Kubernetes ServiceAccount name for SIE workloads"
  type        = string
  default     = "sie-server"
}

# =============================================================================
# GPU Node Groups
# =============================================================================

# --- Legacy single-GPU variables (backward compat) --------------------------
# Used when gpu_node_groups is empty. Existing examples keep working as-is.

variable "gpu_instance_type" {
  description = "EC2 instance type for the GPU node group (g6.xlarge=L4, g5.xlarge=A10G, p4d.24xlarge=A100, p5.48xlarge=H100)"
  type        = string
  default     = "g6.xlarge"
}

variable "gpu_capacity_type" {
  description = "Capacity type for the GPU node group: ON_DEMAND or SPOT"
  type        = string
  default     = "ON_DEMAND"
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.gpu_capacity_type)
    error_message = "gpu_capacity_type must be ON_DEMAND or SPOT"
  }
}

variable "gpu_min_size" {
  description = "Minimum size of the GPU node group (0 enables scale-to-zero)"
  type        = number
  default     = 1
}

variable "gpu_max_size" {
  description = "Maximum size of the GPU node group"
  type        = number
  default     = 10
}

# --- Multi-GPU variable (new) -----------------------------------------------
# When set, overrides the legacy single-GPU variables above.

variable "gpu_node_groups" {
  description = "List of GPU node group configurations. When non-empty, overrides legacy gpu_* variables."
  type = list(object({
    name          = string
    instance_type = string
    capacity_type = optional(string, "SPOT") # Note: legacy gpu_capacity_type defaults to ON_DEMAND
    min_size      = optional(number, 0)
    max_size      = optional(number, 10)
    labels        = optional(map(string), {})
  }))
  default = []

  validation {
    condition = alltrue([
      for g in var.gpu_node_groups : contains(["ON_DEMAND", "SPOT"], g.capacity_type)
    ])
    error_message = "Each gpu_node_groups[*].capacity_type must be ON_DEMAND or SPOT"
  }

  validation {
    condition     = length(var.gpu_node_groups) == length(distinct([for g in var.gpu_node_groups : g.name]))
    error_message = "gpu_node_groups[*].name must be unique"
  }

  validation {
    condition     = alltrue([for g in var.gpu_node_groups : g.name != "cpu"])
    error_message = "gpu_node_groups[*].name must not be \"cpu\" (reserved for the system node group)"
  }
}

variable "kubelet_container_log_max_size" {
  description = "Maximum size of a single kubelet-managed container log file before rotation. Kubelet rotates by size/files, not wall-clock retention."
  type        = string
  default     = "20Mi"

  validation {
    condition     = can(regex("^[1-9][0-9]*(Ei|Pi|Ti|Gi|Mi|Ki|E|P|T|G|M|K)?$", var.kubelet_container_log_max_size))
    error_message = "kubelet_container_log_max_size must be a positive whole-number Kubernetes quantity such as 20Mi."
  }
}

variable "kubelet_container_log_max_files" {
  description = "Maximum number of rotated kubelet-managed container log files to retain per container."
  type        = number
  default     = 30

  validation {
    condition     = var.kubelet_container_log_max_files >= 2 && floor(var.kubelet_container_log_max_files) == var.kubelet_container_log_max_files
    error_message = "kubelet_container_log_max_files must be an integer at least 2."
  }
}

# =============================================================================
# Model cache (S3)
# =============================================================================

variable "create_model_cache" {
  description = "Whether to create the S3 bucket used as the cluster model cache (clusterCache.url in the Helm chart). Default false; flip to true to opt in."
  type        = bool
  default     = false
}

variable "model_cache_bucket_name" {
  description = "Override for the model cache bucket name. When null, generates <project_name>-model-cache-<random 4-byte hex>. Ignored when create_model_cache is false."
  type        = string
  default     = null
}

variable "model_cache_versioning_enabled" {
  description = "Enable S3 versioning on the model cache bucket. Default false; HF cache files are immutable per (repo, sha) so versioning costs storage with no benefit."
  type        = bool
  default     = false
}

variable "model_cache_kms_key_id" {
  description = "KMS key ARN for SSE-KMS on the model cache bucket. When null, uses SSE-S3 (AES256). Public model weights typically don't need KMS."
  type        = string
  default     = null
}
