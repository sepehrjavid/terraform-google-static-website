# TODO

## Changing the certificate's domains fails on an existing deployment

**Status:** not reproduced yet. Inferred from the provider source and the Certificate Manager docs. The e2e cases only create and destroy, so they never hit it.

### When

Any change to the list of domains on `google_certificate_manager_certificate.default`, on a deployment that already exists:

- adding or removing a branch in `branches`;
- turning on `enable_www_redirect` (#10).

### Why

1. `managed.domains` and `managed.dns_authorizations` are `ForceNew` in the provider ([source](https://github.com/hashicorp/terraform-provider-google/blob/main/google/services/certificatemanager/resource_certificate_manager_certificate.go)), so the certificate is replaced.
2. The certificate has a fixed name (`<name_prefix>-website-cert`) and no `create_before_destroy`, so Terraform deletes the old certificate before creating the new one.
3. Certificate Manager refuses that delete while `google_certificate_manager_certificate_map_entry.default` still references the certificate: "Before you delete a certificate, remove it from all certificate map entries that reference it; otherwise, the deletion fails." ([docs](https://cloud.google.com/certificate-manager/docs/certificates))

So the apply most likely fails at the delete. If it got past that, HTTPS would still be down until the new certificate is issued.

### Proposed fix

Use one certificate for `<domain>` and `*.<domain>`, with a single DNS authorization for the domain. A DNS authorization covers its domain and the wildcard, and every branch domain (and `www`) is one label below the domain. After that, adding branches never changes the certificate, and there's one validation record instead of one per branch.

Existing deployments switch certificates once. That needs `create_before_destroy` and a new certificate name, and there's a short window while the new certificate is issued. Document it in the release notes.

Do this after #10 merges, since #10 reworks the same DNS authorization and DNS record code.

To do:

1. Reproduce: add a branch to a running e2e deployment.
2. Confirm in the Certificate Manager docs that a DNS authorization covers its wildcard.
3. Add an e2e case that changes `branches` on an existing deployment.

## A build SA shared by several branches loses its project roles when one branch goes

**Status:** follows from how `google_project_iam_member` works. Applies once #9 merges (it grants the build roles to SAs passed in `build_sa_ids`). Documented in the README under "Build service account roles".

### When

Several branches in `cicd.build_sa_ids` use the same service account, and one of them is removed from `branches` or given another service account.

### Why

The project roles (`roles/logging.logWriter` and the CDN invalidation role) are granted once per branch: `google_project_iam_member.website_log_writer[<branch>]` and `google_project_iam_member.build_sa_cdn_invalidator[<branch>]`. With a shared service account, several resources manage the same role and member, but IAM stores that member only once per role.

Creating and keeping them is harmless: the extra grants are no-ops. Destroying one, though, removes the member from the role for every branch. The other resources are still in the state, so the next plan adds the member back, but until that apply the remaining branches' builds can't write logs or invalidate the CDN cache.

The grants can't be keyed by email to de-duplicate them: SAs created in the same configuration (like the `manual-dns-cicd` e2e case) are only known after apply, and `for_each` keys must be known at plan time.

Bucket grants aren't affected, since each branch has its own bucket.

### Proposed fix

Add an optional `cicd.build_sa_id` (one service account for every branch), mutually exclusive with `build_sa_ids`. With it, the module grants the project roles once, under a fixed key, so removing a branch only removes that branch's bucket grant. That covers the common case of one deploy SA. `build_sa_ids` keeps the current behaviour, for mixed setups.

To do:

1. Add `cicd.build_sa_id` with validation (format, and not together with `build_sa_ids`).
2. Unit tests: one project grant per role with `build_sa_id`; removing a branch leaves the project grants in place.
3. Point the README note on shared service accounts to `build_sa_id`.
