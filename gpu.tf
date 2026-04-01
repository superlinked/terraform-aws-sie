# NVIDIA Device Plugin and GPU Storage
#
# EKS (unlike GKE) does not auto-install the NVIDIA device plugin.
# Without it, GPU nodes don't advertise nvidia.com/gpu resources
# and GPU pods stay Pending.

resource "helm_release" "nvidia_device_plugin" {
  name       = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = "0.17.1"
  namespace  = "kube-system"

  values = [
    yamlencode({
      tolerations = [
        {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    })
  ]

  depends_on = [module.eks]
}

# Default StorageClass — EKS gp2 is not marked default, causing PVCs
# without explicit storageClassName to stay Pending.
resource "kubernetes_annotations" "gp2_default" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "true"
  }

  depends_on = [module.eks]
}
