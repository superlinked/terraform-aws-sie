output "cluster_name" {
  description = "The name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster's Kubernetes API."
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "The base64 encoded CA certificate for the EKS cluster."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "kubectl_config_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

# =============================================================================
# GPU Node Pool
# =============================================================================

output "gpu_node_group_name" {
  description = "Name of the GPU managed node group"
  value       = "gpu"
}

output "gpu_instance_type" {
  description = "EC2 instance type used for GPU nodes"
  value       = var.gpu_instance_type
}

output "gpu_capacity_type" {
  description = "Capacity type for GPU nodes (ON_DEMAND or SPOT)"
  value       = var.gpu_capacity_type
}

output "gpu_node_group_disk_sizes_gb" {
  description = "Root EBS volume size in GiB for each effective GPU node group."
  value       = { for g in local.effective_gpu_groups : g.name => g.disk_size_gb }
}

# =============================================================================
# Container Registry
# =============================================================================

output "ecr_server_repository_url" {
  description = "ECR repository URL for sie-server images"
  value       = local.ecr_server_repository_url
}

output "ecr_gateway_repository_url" {
  description = "ECR repository URL for sie-gateway images"
  value       = local.ecr_gateway_repository_url
}

output "ecr_config_repository_url" {
  description = "ECR repository URL for sie-config images"
  value       = local.ecr_config_repository_url
}

# =============================================================================
# Model cache (S3)
# =============================================================================

output "model_cache_bucket_name" {
  description = "Name of the S3 bucket used as the cluster model cache (null when create_model_cache=false)."
  value       = try(module.model_cache_bucket[0].s3_bucket_id, null)
}

output "model_cache_bucket_url" {
  description = "S3 URL of the model cache bucket WITH the /models prefix - pass to Helm as workers.common.clusterCache.url, and to sie-admin as --target."
  value       = try("s3://${module.model_cache_bucket[0].s3_bucket_id}/models", null)
}

output "payload_store_url" {
  description = "S3 URL of the payload store (the model cache bucket under the /payloads prefix). The chart auto-derives this from clusterCache.url, so a Helm install does not need to set it; output is exposed for visibility and for the rare override case."
  value       = try("s3://${module.model_cache_bucket[0].s3_bucket_id}/payloads", "")
}
