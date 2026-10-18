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

Build on #10's `local.domains`, which now drives the DNS authorizations, host rules and DNS records.

To do:

1. Reproduce: add a branch to a running e2e deployment.
2. Confirm in the Certificate Manager docs that a DNS authorization covers its wildcard.
3. Add an e2e case that changes `branches` on an existing deployment.

## The GitHub token can access every repository its owner can

**Status:** inherent to the current CI/CD setup. Applies when the module creates the GitHub connection (`cicd.github_config`).

### Why

The README asks for a personal access token (classic) with the `repo`, `read:user` and `read:org` scopes. A classic token's `repo` scope gives read and write access to every repository its owner can access, not just the site's. The module stores the token in Secret Manager in the project, so anyone who can read that secret can use it.

### Proposed fix

1. Check whether Cloud Build GitHub connections accept a fine-grained token limited to the site's repository. If they do, recommend it in the README instead of a classic token.
2. Either way, consider deploying from GitHub Actions with Workload Identity Federation as an alternative to Cloud Build. It needs no token: the workflow exchanges GitHub's OIDC token for short-lived credentials, limited to the repository and branch.

## A build can invalidate the CDN cache of every URL map in the project

**Status:** by design today. URL maps have no IAM policy of their own, so the CDN invalidation role is granted on the project.

### Why

Every build service account can invalidate the cache of any URL map in the project: production's, since all branches share one URL map, and other load balancers' in the same project. It can't change content, but a build could keep purging production's cache, which causes cache misses, more load on the buckets and higher cost.

### Proposed fix

To do:

1. Check whether IAM conditions support Compute Engine URL maps and `compute.urlMaps.invalidateCache`. If they do, add a condition on `resource.name` that limits the grant to this module's URL map, which protects other load balancers in the project.
2. That still lets one branch's build invalidate another branch's paths, since all branches share the URL map. Check whether anything can limit invalidation to a branch's own host; if not, document it in the README.

## Browsers cache fingerprinted assets for an hour, not a year

**Status:** seen on a real deploy. Cloud CDN's defaults, not a module bug.

### Why

The backend buckets use Cloud CDN's default cache settings: `CACHE_ALL_STATIC`, `client_ttl` 3600 and `max_ttl` 86400. In that mode Cloud CDN caps the `max-age` it sends to browsers at `client_ttl`, so an asset uploaded with `public, max-age=31536000, immutable` reaches browsers as `public,max-age=3600,immutable`. Fingerprinted files are revalidated every hour: correct, but slower than it could be.

### Proposed fix

To do:

1. Check `cdn_policy` on `google_compute_backend_bucket` (`cache_mode`, `client_ttl`, `default_ttl`, `max_ttl`) in the provider and Cloud CDN docs, including which changes force replacement.
2. Raise `client_ttl` and `max_ttl` (up to a year) so the uploaded `Cache-Control` decides, or expose them as inputs. Objects with `no-cache`, like `index.html`, are revalidated either way.
