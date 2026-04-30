# SIE EKS Terraform Module

One command to get a GPU-ready EKS cluster for [SIE](https://github.com/superlinked/sie) (Search Inference Engine). The module creates everything you need — VPC, EKS, GPU nodes, container registry, autoscaling — so you can focus on running inference, not managing infrastructure.

## What you get

- **EKS cluster** (Kubernetes 1.35) with private networking and KMS-encrypted secrets
- **GPU node group** — pick your GPU: g6 (L4), g5 (A10G), p4d (A100), or p5 (H100)
- **Scale-to-zero** — GPU nodes scale down to zero when idle, so you only pay when running inference
- **Cluster Autoscaler** — automatically scales node groups based on pending pod demand
- **NVIDIA device plugin** — pre-installed so GPU pods schedule immediately
- **ECR repositories** — private container registries for `sie-server` and `sie-gateway` images
- **IRSA** (IAM Roles for Service Accounts) — pods authenticate to AWS without stored credentials
- **VPC endpoints** — private connectivity to ECR, S3, STS, and other AWS services
- **EBS CSI driver** — persistent volumes work out of the box

## Quick start

```bash
cd examples/dev-g6-spot
export AWS_REGION="eu-central-1"   # or your preferred region
terraform init
terraform plan
terraform apply
```

That's it. After apply, configure kubectl and deploy SIE via Helm:

```bash
# Point kubectl at the new cluster
$(terraform output -raw kubectl_config_command)

# Deploy SIE (gateway, workers, KEDA, Prometheus, Grafana)
helm upgrade --install sie-cluster oci://ghcr.io/superlinked/charts/sie-cluster --version 0.3.1 \
  -f values-aws.yaml \
  --create-namespace -n sie \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$(terraform output -raw sie_irsa_role_arn)"
```

## Examples

| Example | GPU | Cost | Description |
|---------|-----|------|-------------|
| [`dev-g6-spot`](examples/dev-g6-spot/) | L4 (g6.xlarge) | ~$0.30/hr | Spot instances, scale 0-5 nodes, minimal cost for development |

## Prerequisites

1. **AWS credentials** configured (`aws configure`, environment variables, or IAM role)
2. **GPU quota** in your target region — check EC2 limits for your chosen instance type
3. **Terraform** >= 1.14

## Variables

### Required

No variables are strictly required — all have sensible defaults. Override these for your environment:

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `eu-central-1` | AWS region to deploy in |
| `project_name` | `sie` | Name prefix for all resources (EKS cluster, IAM roles, etc.) |

### GPU configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `gpu_instance_type` | `g6.xlarge` | EC2 instance type for GPU nodes |
| `gpu_capacity_type` | `ON_DEMAND` | `ON_DEMAND` or `SPOT` (spot saves ~60-70%) |
| `gpu_min_size` | `1` | Minimum GPU nodes — set to `0` for scale-to-zero |
| `gpu_max_size` | `10` | Maximum GPU nodes |

**GPU instance cheat sheet:**

| Instance | GPU | VRAM | Approx. on-demand/hr | Best for |
|----------|-----|------|----------------------|----------|
| `g6.xlarge` | 1x L4 | 24 GB | $0.80 | Development, small models |
| `g5.xlarge` | 1x A10G | 24 GB | $1.00 | Development, medium models |
| `p4d.24xlarge` | 8x A100 | 320 GB | $32.77 | Large models, production |
| `p5.48xlarge` | 8x H100 | 640 GB | $98.32 | Maximum throughput |

### Container registry

| Variable | Default | Description |
|----------|---------|-------------|
| `server_ecr_repository_name` | `sie-server` | ECR repo name for the inference server |
| `gateway_ecr_repository_name` | `sie-gateway` | ECR repo name for the request gateway |
| `config_ecr_repository_name` | `sie-config` | ECR repo name for the sie-config control plane image |

### Workload identity

| Variable | Default | Description |
|----------|---------|-------------|
| `sie_namespace` | `sie` | Kubernetes namespace for SIE workloads |
| `sie_service_account_name` | `sie-server` | K8s ServiceAccount that assumes the IRSA role |

## Outputs

After `terraform apply`, use these outputs to connect and deploy:

| Output | Description |
|--------|-------------|
| `kubectl_config_command` | Run this to configure kubectl |
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | Kubernetes API endpoint (sensitive) |
| `ecr_server_repository_url` | Where to push `sie-server` images |
| `ecr_gateway_repository_url` | Where to push `sie-gateway` images |
| `ecr_config_repository_url` | Where to push `sie-config` images |
| `sie_irsa_role_arn` | Pass to Helm for workload identity |
| `cluster_autoscaler_irsa_role_arn` | Cluster autoscaler IAM role |
| `gpu_instance_type` | Confirm which GPU type is deployed |
| `gpu_capacity_type` | Confirm ON_DEMAND vs SPOT |

## Architecture

```
                         ┌─────────────────────────────────────────────────────┐
                         │                    AWS Region                       │
                         │                                                     │
┌──────────┐             │  ┌───────────────────────────────────────────────┐  │
│          │   HTTPS     │  │                 VPC (10.0.0.0/16)             │  │
│  Client  │────────────▶│  │                                               │  │
│          │             │  │  ┌──────────────────────────────────────────┐ │  │
└──────────┘             │  │  │     EKS Cluster (private + public)       │ │  │
                         │  │  │                                          │ │  │
                         │  │  │  ┌────────────┐    ┌─────────────────┐   │ │  │
                         │  │  │  │   Gateway   │───▶│  GPU Workers    │   │ │  │
                         │  │  │  │            │    │  (L4/A10G/A100) │   │ │  │
                         │  │  │  └─────┬──────┘    └─────────────────┘   │ │  │
                         │  │  │        │                    │            │ │  │
                         │  │  │  ┌─────┴──────┐              │            │ │  │
                         │  │  │  │ sie-config │ (control plane, NATS)    │ │  │
                         │  │  │  └────────────┘              │            │ │  │
                         │  │  │                              │            │ │  │
                         │  │  │  ┌────────────────────────────────────┐   │ │  │
                         │  │  │  │  KEDA · Prometheus · Grafana       │   │ │  │
                         │  │  │  └────────────────────────────────────┘   │ │  │
                         │  │  │                                          │ │  │
                         │  │  │  ┌──────────────┐  ┌─────────────────┐   │ │  │
                         │  │  │  │  CPU Nodes   │  │  GPU Nodes      │   │ │  │
                         │  │  │  │  (t3.xlarge) │  │  (g6/g5/p4d/p5) │   │ │  │
                         │  │  │  └──────────────┘  └─────────────────┘   │ │  │
                         │  │  └──────────────────────────────────────────┘ │  │
                         │  │                                               │  │
                         │  │  ┌───────────┐  ┌───────────┐  ┌──────────┐   │  │
                         │  │  │    ECR    │  │   KMS     │  │  NAT GW  │   │  │
                         │  │  │ (images)  │  │ (secrets) │  │ (egress) │   │  │
                         │  │  └───────────┘  └───────────┘  └──────────┘   │  │
                         │  └───────────────────────────────────────────────┘  │
                         └─────────────────────────────────────────────────────┘
```

## Pushing images to ECR
> This is optional, because the official image is available at `ghcr.io/superlinked/`.

After `terraform apply`, push your SIE Docker images:

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region $(terraform output -raw aws_region 2>/dev/null || echo $AWS_REGION) \
  | docker login --username AWS --password-stdin $(terraform output -raw ecr_server_repository_url | cut -d/ -f1)

# Push server image
docker tag sie-server:latest $(terraform output -raw ecr_server_repository_url):latest
docker push $(terraform output -raw ecr_server_repository_url):latest

# Push gateway image
docker tag sie-gateway:latest $(terraform output -raw ecr_gateway_repository_url):latest
docker push $(terraform output -raw ecr_gateway_repository_url):latest

# Push sie-config image
docker tag sie-config:latest $(terraform output -raw ecr_config_repository_url):latest
docker push $(terraform output -raw ecr_config_repository_url):latest
```

## Security features

This module follows AWS security best practices out of the box:

- **KMS encryption** — EKS secrets encrypted at rest with a dedicated, auto-rotating KMS key
- **Private subnets** — worker nodes run in private subnets with no public IPs
- **NAT gateway** — outbound internet via NAT (one per AZ for high availability)
- **VPC endpoints** — private access to ECR, S3, STS, EC2, CloudWatch, and other services
- **IRSA** — pods use IAM roles instead of long-lived credentials
- **GPU taints** — GPU nodes are tainted so only GPU workloads schedule on them
- **Image scanning** — ECR scans images on push for known vulnerabilities
- **Audit logging** — all EKS control plane log types enabled

## Cleanup

```bash
terraform destroy
```

**Important**: GPU instances can be expensive. Always destroy dev/test clusters when not in use. Spot instances (`gpu_capacity_type = "SPOT"`) save 60-70% but may be interrupted.
