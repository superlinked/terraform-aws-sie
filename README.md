# SIE EKS Terraform Module

One command to get a GPU-ready EKS cluster for [SIE](https://github.com/superlinked/sie) (Search Inference Engine). The module creates everything you need - VPC, EKS, GPU nodes, container registry, autoscaling - so you can focus on running inference, not managing infrastructure.

## What you get

- **EKS cluster** (Kubernetes 1.35) with private networking and KMS-encrypted secrets
- **GPU node group** - pick your GPU: g6 (L4), g5 (A10G), p4d (A100), or p5 (H100)
- **Scale-to-zero** - GPU nodes scale down to zero when idle, so you only pay when running inference
- **Cluster Autoscaler** - automatically scales node groups based on pending pod demand
- **NVIDIA device plugin** - pre-installed so GPU pods schedule immediately
- **ECR repositories** (opt-in) - private container registries for customer-built images (`<project_name>/sie-server`, `<project_name>/sie-gateway`, `<project_name>/sie-config`). Off by default; set `create_ecr_repositories = true` to opt in. The worker-sidecar image stays on the chart's public GHCR default.
- **IRSA** (IAM Roles for Service Accounts) - pods authenticate to AWS without stored credentials
- **VPC endpoints** - private connectivity to ECR, S3, STS, and other AWS services
- **EBS CSI driver** - persistent volumes work out of the box

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
helm upgrade --install sie-cluster oci://ghcr.io/superlinked/charts/sie-cluster --version 0.6.5 \
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
2. **GPU quota** in your target region - check EC2 limits for your chosen instance type
3. **Terraform** >= 1.14

## Variables

### Required

No variables are strictly required - all have sensible defaults. Override these for your environment:

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `eu-central-1` | AWS region to deploy in |
| `project_name` | `sie` | Name prefix for all resources (EKS cluster, IAM roles, etc.) |

### GPU configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `gpu_instance_type` | `g6.xlarge` | EC2 instance type for GPU nodes |
| `gpu_capacity_type` | `ON_DEMAND` | `ON_DEMAND` or `SPOT` (spot saves ~60-70%) |
| `gpu_min_size` | `1` | Minimum GPU nodes - set to `0` for scale-to-zero |
| `gpu_max_size` | `10` | Maximum GPU nodes |
| `gpu_disk_size_gb` | `100` | Root EBS volume size for the legacy single GPU node group |
| `gpu_disk_type` | `gp3` | Root EBS volume type for the legacy single GPU node group |

For multi-pool clusters, set `gpu_node_groups[*].disk_size_gb` and
`gpu_node_groups[*].disk_type` per pool. This mirrors the GCP module's
`gpu_node_pools[*].disk_size_gb` / `disk_type` shape and is the knob that
backs Kubernetes `emptyDir` model caches on EKS nodes.

### Networking

| Variable | Default | Description |
|----------|---------|-------------|
| `vpc_cidr` | `10.0.0.0/16` | CIDR block for the EKS VPC |
| `private_subnet_prefix_length` | `20` | Private worker subnet size; default creates `/20` private subnets for EKS pod IP headroom |
| `public_subnet_prefix_length` | `24` | Public subnet size; default creates `/24` public subnets for load balancers/NAT |

Changing VPC/subnet sizing is intentionally breaking for existing clusters because AWS subnet CIDRs are replacement-sensitive. Recreate ephemeral clusters or plan a migration window for persistent clusters.

### Node log rotation

| Variable | Default | Description |
|----------|---------|-------------|
| `kubelet_container_log_max_size` | `20Mi` | Per-container kubelet log file size before rotation |
| `kubelet_container_log_max_files` | `30` | Rotated files retained per container; kubelet retention is size/count based, not hourly |

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
| `create_ecr_repositories` | `false` | Whether this module manages the ECR repos. Default `false` matches the chart's GHCR-by-default behaviour and avoids `RepositoryAlreadyExistsException` on accounts where the repos already exist. Set `true` to opt in. The `ecr_*_repository_url` outputs are emitted regardless. |
| `ecr_repository_prefix` | `null` -> `<project_name>` | Namespace prefix for ECR repo names; final names become `<prefix>/<repo_name>`. Set to `""` to disable prefixing (bare names) for accounts where ECR is externally managed. |

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
| `gpu_node_group_disk_sizes_gb` | Root EBS volume size per effective GPU node group |

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
> This is optional, because the official images are available under `ghcr.io/superlinked/`.

Requires `create_ecr_repositories = true` (or repos managed by another stack - see `ecr_repository_prefix`).

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

## Model cache and payload store

SIE clusters benefit from two object-store backed features that share a single S3 bucket:

- **Model cache**: pre-staged model weights at `s3://<bucket>/models/`, so workers cold-start from object storage rather than re-downloading from Hugging Face on every pod spin-up.
- **Payload store**: large work-item payloads (images, long documents that exceed the 1 MiB NATS in-band budget) at `s3://<bucket>/payloads/`, written by the gateway and read once by the worker. Garbage-collected by a runtime TTL plus a bucket lifecycle rule.

Set `create_model_cache = true` and the module:

1. Provisions a managed S3 bucket with versioning, abort-incomplete-multipart, and a lifecycle rule that deletes objects under the `payloads/` prefix after one day.
2. Attaches two scoped inline policies to the SIE workload IRSA role: read-only on the cache, and `s3:Get/Put/Delete/AbortMultipartUpload` constrained to the `payloads/*` prefix, with a `ListBucket` prefix condition.
3. KMS-encrypted buckets get matching `kms:Decrypt/Encrypt/GenerateDataKey` grants.

After apply, pass the bucket into Helm with one terraform output:

```bash
helm upgrade --install sie-cluster ../../deploy/helm/sie-cluster \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$(terraform output -raw sie_irsa_role_arn)" \
  $(terraform output -raw model_cache_helm_args)
```

The chart auto-derives `payloadStore.url` from `workers.common.clusterCache.url`, so a single `--set` for the cache covers both features. Operators who do not opt in (`create_model_cache = false`, default) skip the bucket and IAM additions entirely; the chart treats the absence as "payload store off".

See `infra/s3_model_cache.tf` and `infra/irsa.tf` for the resource definitions.

## Security features

This module follows AWS security best practices out of the box:

- **KMS encryption** - EKS secrets encrypted at rest with a dedicated, auto-rotating KMS key
- **Private subnets** - worker nodes run in private subnets with no public IPs
- **NAT gateway** - outbound internet via NAT (one per AZ for high availability)
- **VPC endpoints** - private access to ECR, S3, STS, EC2, CloudWatch, and other services
- **IRSA** - pods use IAM roles instead of long-lived credentials
- **GPU taints** - GPU nodes are tainted so only GPU workloads schedule on them
- **Image scanning** - ECR scans images on push for known vulnerabilities
- **Audit logging** - all EKS control plane log types enabled

## Bring-your-own components

Some pieces of a production deployment are intentionally not turnkey - either because they're cluster-wide / cross-stack concerns (registry, OIDC) or because they require domains and DNS records that only you can own (TLS, DNS). This module lets you opt out where it makes sense and points at the right knobs.

- **Container registry** - optional. The module does **not** create ECR repos by default (`create_ecr_repositories = false`, see [`infra/variables.tf`](infra/variables.tf)) - this matches the chart's GHCR-by-default behaviour and avoids `RepositoryAlreadyExistsException` on accounts where repos already exist. Set `create_ecr_repositories = true` to opt in to terraform-managed ECR; the module will create project-scoped repos (`<project_name>/sie-server`, `<project_name>/sie-gateway`, `<project_name>/sie-config`). Override the namespace via `ecr_repository_prefix` - set to `""` to disable prefixing for accounts where ECR is externally managed under bare names. The module always emits `ecr_*_repository_url` outputs (composed from caller identity + repo names) so IRSA / Helm wiring is unchanged whether you opt in or not. The worker-sidecar uses the chart's `ghcr.io/superlinked/sie-server-sidecar` default; to use an external registry for the other runtime images, point the Helm chart at it via `gateway.image.repository`, `workers.common.image.repository`, and `config.image.repository`.
- **TLS certificate** - BYO by default. Set `ingress.tlsConfig.mode` to one of:
  - `byo` - supply your own `kubernetes.io/tls` Secret.
  - `cert-manager` - install cert-manager once in the cluster; the chart annotates the Ingress for automated Let's Encrypt issuance via HTTP-01.
  - `self-signed` - for air-gapped clusters; set `certManagerBundle.certManager.install: true` to bundle cert-manager (single-tenant clusters only).

  See the [chart README's TLS / HTTPS section](../../helm/sie-cluster/README.md#tls--https). DNS-01 / wildcard / ACM paths are out of scope for the chart.
- **DNS / domain** - always BYO. This module does not provision Route53 zones or records. After `terraform apply`, take the ingress controller's LoadBalancer hostname (`kubectl -n ingress-nginx get svc ingress-nginx-controller`) and create an A/AAAA record pointing at it under a domain you control.
- **OIDC provider** - BYO. When `auth.enabled: true` in the chart, set `auth.oauth2Proxy.oidcIssuerUrl` and the corresponding client ID / secret to your existing identity provider (Okta, Auth0, Google Workspace, Azure AD, ...). The module does not create an IdP.

## Cleanup

```bash
terraform destroy
```

**Important**: GPU instances can be expensive. Always destroy dev/test clusters when not in use. Spot instances (`gpu_capacity_type = "SPOT"`) save 60-70% but may be interrupted.
