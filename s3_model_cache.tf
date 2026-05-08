# S3 bucket used as the cluster model cache.
# Workers read via the workload IRSA role (read-only, scoped to this bucket).
# Operators populate from a laptop with `sie-admin cache populate --target s3://.../models/`.
# Opt-in: gated on var.create_model_cache.

locals {
  # Normalize optional string inputs: treat null and whitespace-only the same.
  # Without this, `coalesce` would accept "  " as a valid bucket name and the
  # SSE-KMS branch would emit `kms_master_key_id = "  "` at apply time.
  normalized_model_cache_bucket_name = (
    var.model_cache_bucket_name == null || trimspace(var.model_cache_bucket_name) == ""
    ? null
    : trimspace(var.model_cache_bucket_name)
  )
  normalized_model_cache_kms_key_id = (
    var.model_cache_kms_key_id == null || trimspace(var.model_cache_kms_key_id) == ""
    ? null
    : trimspace(var.model_cache_kms_key_id)
  )
}

resource "random_id" "model_cache_suffix" {
  count       = var.create_model_cache && local.normalized_model_cache_bucket_name == null ? 1 : 0
  byte_length = 4
}

locals {
  model_cache_bucket_name = (
    var.create_model_cache
    ? coalesce(local.normalized_model_cache_bucket_name, "${var.project_name}-model-cache-${try(random_id.model_cache_suffix[0].hex, "")}")
    : null
  )
}

module "model_cache_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.0"

  count = var.create_model_cache ? 1 : 0

  bucket = local.model_cache_bucket_name

  # ACLs disabled, owner-enforced
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  # Block all public access
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # Encryption: SSE-S3 by default, SSE-KMS when a non-empty key is supplied
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = (
        local.normalized_model_cache_kms_key_id == null
        ? { sse_algorithm = "AES256" }
        : { sse_algorithm = "aws:kms", kms_master_key_id = local.normalized_model_cache_kms_key_id }
      )
    }
  }

  # Versioning toggle
  versioning = {
    enabled = var.model_cache_versioning_enabled
  }

  # Lifecycle: clean up failed multipart uploads after 7 days.
  # Note: terraform-aws-modules/s3-bucket v5 expects the flat key
  # `abort_incomplete_multipart_upload_days`; the nested object form is silently
  # ignored and produces a rule with no actions (AWS InvalidRequest at apply).
  lifecycle_rule = [
    {
      id                                     = "abort-incomplete-multipart"
      enabled                                = true
      abort_incomplete_multipart_upload_days = 7
    }
  ]

  # TLS-only access (deny non-TLS requests)
  attach_deny_insecure_transport_policy = true

  tags = {
    Name    = local.model_cache_bucket_name
    Purpose = "SIE cluster model cache"
  }
}
