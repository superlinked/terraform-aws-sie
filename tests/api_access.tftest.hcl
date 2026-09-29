# SIE EKS Terraform - Kubernetes API access tests
#
# Run with: terraform test -filter=tests/api_access.tftest.hcl
# Uses mock providers, so no cloud credentials are needed.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    }
  }

  mock_data "aws_ec2_instance_type_offerings" {
    defaults = {
      locations = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test"
    }
  }

  mock_data "aws_iam_session_context" {
    defaults = {
      arn        = "arn:aws:iam::123456789012:user/test"
      issuer_arn = "arn:aws:iam::123456789012:user/test"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name   = "eu-central-1"
      region = "eu-central-1"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "random" {}

variables {
  project_name = "sie-test"
}

# =============================================================================
# Rejected configurations
# =============================================================================

run "rejects_unset_api_access" {
  command = plan

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_ipv4_any_address_without_opt_in" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["0.0.0.0/0"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_split_any_address_without_opt_in" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["0.0.0.0/1", "128.0.0.0/1"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_aggregate_above_one_slash8_without_opt_in" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["11.0.0.0/8", "12.0.0.0/8"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_ipv6_any_address" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["::/0"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_ipv6_range_for_ipv4_cluster" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["2001:4860::/32"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_ipv6_range_even_with_opt_in" {
  command = plan

  variables {
    allow_public_api_server         = true
    api_server_authorized_ip_ranges = ["2001:4860::/32"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_malformed_range" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["8.8.8.8"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_documentation_placeholder" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["203.0.113.10/32"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_more_than_40_ranges" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = [for i in range(41) : cidrsubnet("8.0.0.0/8", 16, i)]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_private_endpoint_with_public_ranges" {
  command = plan

  variables {
    enable_private_endpoint         = true
    api_server_authorized_ip_ranges = ["8.8.8.8/32"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

# =============================================================================
# Accepted configurations
# =============================================================================

run "restricts_public_endpoint_to_allowlist" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["8.8.8.8/32", "9.9.9.0/24"]
  }

  assert {
    condition = (
      output.api_server_access.public_endpoint_enabled
      && output.api_server_access.public_access_cidrs == tolist(["8.8.8.8/32", "9.9.9.0/24"])
    )
    error_message = "The public endpoint should accept only the allowlisted ranges"
  }
}

run "accepts_allowlist_totalling_one_slash8" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["11.0.0.0/9", "11.128.0.0/9"]
  }

  assert {
    condition     = output.api_server_access.public_access_cidrs == tolist(["11.0.0.0/9", "11.128.0.0/9"])
    error_message = "An allowlist covering exactly one /8 should be accepted"
  }
}

run "private_endpoint_disables_public_endpoint" {
  command = plan

  variables {
    enable_private_endpoint = true
  }

  assert {
    condition     = !output.api_server_access.public_endpoint_enabled && output.api_server_access.public_access_cidrs == null
    error_message = "enable_private_endpoint should disable the public endpoint"
  }
}

run "opt_in_allows_any_address" {
  command = plan

  variables {
    allow_public_api_server = true
  }

  assert {
    condition     = output.api_server_access.public_endpoint_enabled && output.api_server_access.public_access_cidrs == tolist(["0.0.0.0/0"])
    error_message = "allow_public_api_server with no allowlist should open the public endpoint to any address"
  }
}

run "opt_in_accepts_broad_allowlist" {
  command = plan

  variables {
    allow_public_api_server         = true
    api_server_authorized_ip_ranges = ["11.0.0.0/8", "12.0.0.0/8"]
  }

  assert {
    condition     = output.api_server_access.public_access_cidrs == tolist(["11.0.0.0/8", "12.0.0.0/8"])
    error_message = "allow_public_api_server should accept an allowlist broader than one /8"
  }
}

run "eks_module_receives_the_derived_access_values" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["8.8.8.8/32"]
  }

  # Test assertions cannot read resources inside the upstream EKS module, so
  # this pins the module arguments to the values the output above reports.
  assert {
    condition = (
      output.api_server_access.public_endpoint_enabled
      && can(regex("\n  endpoint_public_access +=[ ]+local\\.endpoint_public_access\n", file("eks.tf")))
      && can(regex("\n  endpoint_public_access_cidrs +=[ ]+local\\.endpoint_public_access_cidrs\n", file("eks.tf")))
      && can(regex("\n  endpoint_private_access +=[ ]+true\n", file("eks.tf")))
    )
    error_message = "module.eks must take endpoint_public_access and endpoint_public_access_cidrs from the derived locals and keep the private endpoint enabled"
  }
}
