# Development Cluster with G6 Spot GPUs

Creates a minimal EKS cluster with a single g6.xlarge spot GPU node group (NVIDIA L4) — ideal for development and testing SIE (Search Inference Engine) workloads at low cost.

## What this example creates

| Resource | Configuration |
|----------|---------------|
| EKS cluster | Private subnets, KMS-encrypted secrets, Kubernetes 1.35 |
| GPU node group | 1x NVIDIA L4 per node (g6.xlarge), spot instances, scale 0-5 |
| CPU node group | t3.xlarge (system workloads), scale 1-5 |
| VPC | 2 AZs, public + private subnets, NAT gateway, VPC endpoints |
| ECR | Repositories for `sie-server` and `sie-router` images |
| Cluster Autoscaler | Auto-scales node groups based on pending pods |
| NVIDIA device plugin | GPU scheduling support |
| IRSA | IAM roles for SIE and EBS CSI driver |

**Estimated cost**: ~$0.30/hr when a GPU node is running. Near $0/hr when scaled to zero (only EKS control plane fee applies).

## Usage

```bash
terraform init
terraform plan
terraform apply
```

After apply, deploy SIE via Helm:

```bash
# Configure kubectl
$(terraform output -raw kubectl_config_command)

# Install SIE (router, workers, KEDA, Prometheus, Grafana)
helm upgrade --install sie-cluster oci://ghcr.io/superlinked/charts/sie-cluster --version 0.1.10 \
  --namespace sie --create-namespace \
  -f values-aws.yaml \
  --create-namespace -n sie \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$(terraform output -raw sie_irsa_role_arn)"
```

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `eu-central-1` | AWS region |
| `project_name` | `sie-dev` | Name prefix for all resources |

## Outputs

| Output | Description |
|--------|-------------|
| `cluster_name` | EKS cluster name |
| `kubectl_config_command` | Run this to configure kubectl |
| `cluster_endpoint` | Kubernetes API endpoint (sensitive) |
| `sie_irsa_role_arn` | Pass to Helm for workload identity |
| `cluster_autoscaler_irsa_role_arn` | Cluster autoscaler IAM role |

## Customizing

**Change region:**

```hcl
variable "aws_region" {
  default = "us-west-2"
}
```

**Use on-demand instead of spot (more reliable, higher cost):**

```hcl
module "sie_eks" {
  source = "superlinked/sie/aws"

  gpu_capacity_type = "ON_DEMAND"
  # ... other variables
}
```

**Use a larger GPU (A10G instead of L4):**

```hcl
module "sie_eks" {
  source = "superlinked/sie/aws"

  gpu_instance_type = "g5.xlarge"
  # ... other variables
}
```

## Prerequisites

1. AWS credentials configured (`aws configure` or environment variables)
2. EC2 quota for `g6.xlarge` in your target region
3. Terraform >= 1.14

## Cleanup

```bash
terraform destroy
```
