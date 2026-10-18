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
