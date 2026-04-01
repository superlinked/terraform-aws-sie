# Cluster Autoscaler for EKS
#
# GKE has built-in node autoprovisioning; EKS requires an explicit deployment.
# The autoscaler watches for unschedulable pods and scales node groups up/down.
# The IRSA role grants the autoscaler permission to modify EC2 Auto Scaling Groups.

variable "cluster_autoscaler_version" {
  description = "Version of the cluster-autoscaler Helm chart"
  type        = string
  default     = "9.43.2"
}

# IRSA role for cluster autoscaler
module "cluster_autoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.4.0"

  name = "${var.project_name}-cluster-autoscaler"

  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.cluster_autoscaler_version
  namespace  = "kube-system"

  values = [
    yamlencode({
      autoDiscovery = {
        clusterName = module.eks.cluster_name
      }
      awsRegion = var.aws_region
      rbac = {
        serviceAccount = {
          name = "cluster-autoscaler"
          annotations = {
            "eks.amazonaws.com/role-arn" = module.cluster_autoscaler_irsa.arn
          }
        }
      }
      extraArgs = {
        scale-down-unneeded-time   = "10m"
        scale-down-delay-after-add = "10m"
      }
    })
  ]

  depends_on = [module.eks]
}

output "cluster_autoscaler_irsa_role_arn" {
  description = "ARN of the IAM role for cluster autoscaler"
  value       = module.cluster_autoscaler_irsa.arn
}
