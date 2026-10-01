# Changelog

## [1.0.0](https://github.com/superlinked/terraform-aws-sie/compare/v0.7.3...v1.0.0) (2026-10-01)


### ⚠ BREAKING CHANGES

* the module no longer opens the EKS public API endpoint to 0.0.0.0/0 by default, and the plan fails until an access mode is set. Set api_server_authorized_ip_ranges to the CIDRs that run terraform, kubectl and helm (an in-place update of the cluster's public_access_cidrs), set enable_private_endpoint = true to serve the API only inside the VPC, or set allow_public_api_server = true to keep the previous behaviour with no plan change.

### Bug Fixes

* pin EKS deployment examples to SIE 0.9.0 ([#6](https://github.com/superlinked/terraform-aws-sie/issues/6)) ([d537bba](https://github.com/superlinked/terraform-aws-sie/commit/d537bba007b17046b2c54dc9636487b987e038c2))
* stop opening the EKS API endpoint to every address ([#5](https://github.com/superlinked/terraform-aws-sie/issues/5)) ([ccc3f6b](https://github.com/superlinked/terraform-aws-sie/commit/ccc3f6b5ba0fd89429e1516980d5556fdb6a35f0))

## [0.7.3](https://github.com/superlinked/terraform-aws-sie/compare/v0.7.2...v0.7.3) (2026-09-28)


### Bug Fixes

* pin EKS deployment examples to SIE 0.8.3 ([#4](https://github.com/superlinked/terraform-aws-sie/issues/4)) ([d3d7bbd](https://github.com/superlinked/terraform-aws-sie/commit/d3d7bbd82ac94218f99c1a579bd29f5993580883))
* use SIE 0.8.2 in EKS deployment examples ([#2](https://github.com/superlinked/terraform-aws-sie/issues/2)) ([b36f0b6](https://github.com/superlinked/terraform-aws-sie/commit/b36f0b62a31491a36e2f6e1ea24a304ad9d3a7a4))
