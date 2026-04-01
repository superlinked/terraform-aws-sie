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
# GPU Node Group
# =============================================================================

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
