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
# Kubernetes API Access
# =============================================================================

variable "api_server_authorized_ip_ranges" {
  description = "IPv4 CIDR blocks allowed to reach the EKS public Kubernetes API endpoint, at most 40. Include the egress address of every machine that runs terraform, kubectl, or helm against the cluster: the module installs Helm releases during apply. Leave empty only with enable_private_endpoint = true or allow_public_api_server = true. Together the ranges may cover at most 16,777,216 addresses (one /8) unless allow_public_api_server = true. Documentation ranges (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24) are rejected."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for cidr in var.api_server_authorized_ip_ranges : can(cidrhost(cidr, 0)) && !strcontains(cidr, ":")])
    error_message = "Each api_server_authorized_ip_ranges entry must be an IPv4 CIDR block (an address with a prefix length, such as <egress-address>/32). The module creates an IPv4 cluster, and EKS accepts IPv6 public access CIDRs only for IPv6 clusters."
  }

  validation {
    condition     = length(var.api_server_authorized_ip_ranges) <= 40
    error_message = "api_server_authorized_ip_ranges accepts at most 40 entries: EKS allows 40 public endpoint access CIDR ranges per cluster and the quota is not adjustable (https://docs.aws.amazon.com/general/latest/gr/eks.html#limits_eks)."
  }

  validation {
    condition = alltrue([
      for cidr in var.api_server_authorized_ip_ranges : !try(
        tonumber(split("/", cidr)[1]) >= 24
        && contains(["192.0.2", "198.51.100", "203.0.113"], join(".", slice(split(".", cidrhost(cidr, 0)), 0, 3))),
        false
      )
    ])
    error_message = "api_server_authorized_ip_ranges contains a documentation range (192.0.2.0/24, 198.51.100.0/24, or 203.0.113.0/24), such as the README placeholder. Replace it with the real egress address of the machines that need API access."
  }

  validation {
    condition = var.allow_public_api_server || try(
      sum(concat([0], [for cidr in var.api_server_authorized_ip_ranges : pow(2, 32 - tonumber(split("/", cidr)[1]))])) <= pow(2, 24),
      false
    )
    error_message = "api_server_authorized_ip_ranges covers more than 16,777,216 addresses (one /8) in total, for example 0.0.0.0/0 or several broad ranges. List the specific ranges that need API access, or set allow_public_api_server = true to accept any Internet address."
  }

  validation {
    condition     = var.enable_private_endpoint || var.allow_public_api_server || length(var.api_server_authorized_ip_ranges) > 0
    error_message = "Choose how the Kubernetes API is reached: set api_server_authorized_ip_ranges to the CIDRs that run terraform, kubectl, and helm (for example your egress address as /32), set enable_private_endpoint = true to serve the API only inside the VPC, or set allow_public_api_server = true to accept any Internet address."
  }

  validation {
    condition     = !(var.enable_private_endpoint && length(var.api_server_authorized_ip_ranges) > 0)
    error_message = "api_server_authorized_ip_ranges applies to the public endpoint, which enable_private_endpoint = true disables. Set one or the other."
  }
}

variable "enable_private_endpoint" {
  description = "Serve the Kubernetes API only on the private endpoint inside the VPC and disable the public endpoint. terraform apply must then run from a network that reaches the VPC (VPN, peering, or a runner inside the VPC), because the module installs Helm releases."
  type        = bool
  default     = false
  nullable    = false
}

variable "allow_public_api_server" {
  description = "Opt in to a public Kubernetes API endpoint that accepts any Internet address. With an empty api_server_authorized_ip_ranges the endpoint allows 0.0.0.0/0, and the allowlist may cover more than one /8 in total. Requests still need IAM authentication."
  type        = bool
  default     = false
  nullable    = false
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

variable "gpu_disk_size_gb" {
  description = "Root EBS volume size in GiB for the legacy single GPU node group. Must stay above the Helm chart's `workers.common.cacheStorageSize` (default 300Gi): that model cache is an emptyDir on this root volume, so a smaller disk fills up and kubelet evicts workers on disk pressure long before the emptyDir sizeLimit engages. The 500 default sizes for kubelet's eviction threshold, not just raw capacity: at the default `nodefs.available<10%` only ~90% of the disk is usable, so holding the 300Gi cache plus ~100GiB of OS, container images, and logs needs ceil(400 / 0.9) = 445GiB, and 500 leaves room for filesystem overhead. Use gpu_node_groups[*].disk_size_gb for multi-pool clusters."
  type        = number
  default     = 500

  validation {
    condition     = floor(var.gpu_disk_size_gb) == var.gpu_disk_size_gb && var.gpu_disk_size_gb >= 20
    error_message = "gpu_disk_size_gb must be an integer at least 20."
  }
}

variable "gpu_disk_type" {
  description = "Root EBS volume type for the legacy single GPU node group. Use gpu_node_groups[*].disk_type for multi-pool clusters."
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["standard", "gp2", "gp3", "io1", "io2", "st1", "sc1"], var.gpu_disk_type)
    error_message = "gpu_disk_type must be a valid EBS volume type."
  }
}

# --- Multiple GPU node groups -----------------------------------------------
# When set, overrides the legacy single-GPU variables above.

variable "gpu_node_groups" {
  description = "List of GPU node group configurations. When non-empty, overrides legacy gpu_* variables. This controls node group shape; per-pod multi-GPU scheduling still requires selecting an instance type with enough GPUs and matching Helm workers.pools.<name>.gpu.count. Keep disk_size_gb above the Helm chart's `workers.common.cacheStorageSize` (default 300Gi) for every group that hosts workers — see gpu_disk_size_gb."
  type = list(object({
    name          = string
    instance_type = string
    capacity_type = optional(string, "SPOT") # Note: legacy gpu_capacity_type defaults to ON_DEMAND
    min_size      = optional(number, 0)
    max_size      = optional(number, 10)
    disk_size_gb  = optional(number, 500) # (300Gi cache + ~100GiB OS/images/logs) / 0.9 kubelet eviction headroom
    disk_type     = optional(string, "gp3")
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
    condition = alltrue([
      for g in var.gpu_node_groups : floor(g.disk_size_gb) == g.disk_size_gb && g.disk_size_gb >= 20
    ])
    error_message = "Each gpu_node_groups[*].disk_size_gb must be an integer at least 20."
  }

  validation {
    condition = alltrue([
      for g in var.gpu_node_groups : contains(["standard", "gp2", "gp3", "io1", "io2", "st1", "sc1"], g.disk_type)
    ])
    error_message = "Each gpu_node_groups[*].disk_type must be a valid EBS volume type."
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

variable "observability_node_group" {
  description = <<-EOT
    Optional dedicated single-AZ node group for the stateful observability stack
    (Prometheus/Loki/Grafana/Alertmanager). Their EBS volumes are AZ-locked, and
    a multi-AZ node group can leave the volumes' AZ without a node after a roll or
    scale, orphaning the pods (Pending, PersistentVolume node-affinity conflict).
    Pinning a node group to one AZ with min_size >= 1 guarantees a home. Disabled
    by default so other clusters are unaffected. Steer obs pods onto it with a
    nodeSelector on `sie.superlinked.com/node-type=observability` in Helm values.
  EOT
  type = object({
    enabled           = optional(bool, false)
    availability_zone = optional(string, null) # e.g. "us-east-2c"; defaults to the first VPC AZ
    instance_type     = optional(string, "t3.xlarge")
    ami_type          = optional(string, null) # default: the AL2023 family matching the instance architecture (x86_64 or arm64); set explicitly for e.g. Bottlerocket
    min_size          = optional(number, 1)
    max_size          = optional(number, 2)
    disk_size_gb      = optional(number, 100)
    disk_type         = optional(string, "gp3")
  })
  default = {}

  validation {
    condition     = !var.observability_node_group.enabled || var.observability_node_group.min_size >= 1
    error_message = "observability_node_group.min_size must be >= 1 when enabled, so the AZ-locked observability volumes always have a node to bind to."
  }

  validation {
    condition     = var.observability_node_group.max_size >= var.observability_node_group.min_size
    error_message = "observability_node_group.max_size must be >= observability_node_group.min_size."
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
  description = "Create the S3 bucket backing the optional model-weights cache (models/) and the payload store for work items >1MB (payloads/). The payload store is required for large payloads such as images, so this defaults to true. Set false only if you bring your own object-storage bucket (and wire payloadStore.url) or accept that >1MB requests fail."
  type        = bool
  default     = true
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
