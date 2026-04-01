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

# =============================================================================
# Container Registry
# =============================================================================

output "ecr_server_repository_url" {
  description = "ECR repository URL for sie-server images"
  value       = aws_ecr_repository.server.repository_url
}

output "ecr_router_repository_url" {
  description = "ECR repository URL for sie-router images"
  value       = aws_ecr_repository.router.repository_url
}
