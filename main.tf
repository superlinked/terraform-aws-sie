# SIE AWS Infrastructure — EKS, VPC, IAM, ECR, Cluster Autoscaler
#
# Cloud-level resources + EKS-specific K8s infrastructure (Cluster Autoscaler).
# User-facing K8s workloads (KEDA, Prometheus, SIE) are deployed separately
# via: helm upgrade --install sie-cluster oci://ghcr.io/superlinked/charts/sie-cluster --version 0.8.2
# See examples/ for complete usage.

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}
