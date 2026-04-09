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

variable "router_ecr_repository_name" {
  description = "The name of the ECR repository for the sie-router."
  type        = string
  default     = "sie-router"
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
