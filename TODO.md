# TODO

## Removing a branch fails on an existing deployment

**Status:** seen on a real deployment, also with 3.0.

### When

Removing a branch from `branches` on a deployment that already exists.

### Why

Terraform deletes the branch's backend bucket before it updates the URL map, which still routes to it, and the API refuses: "The backend_bucket resource '...-dev-backend' is already being used by '...-https-lb', resourceInUseByAnotherResource". That's Terraform's order for a deleted resource without `create_before_destroy`. Targeting the URL map doesn't help, because the target includes the backend buckets it depends on. `terraform destroy` works, since it deletes the URL map first.

### Proposed fix

To do:

1. Try `create_before_destroy` on `google_compute_backend_bucket.backends`, so the URL map is updated before the backend bucket is deleted. Terraform reads the setting from the state for a deleted instance, so existing backend buckets need an in-place update first for it to apply to them. Check the order with `terraform graph -type=apply -plan=<plan>`.
2. `create_before_destroy` also applies to the buckets the backend buckets depend on: check what that means when a bucket is replaced.
3. Change the e2e update step to remove a branch once it works.

## Changing the domain fails on an existing deployment

**Status:** not reproduced yet. Inferred from the provider source.

### When

Changing the domain (`dns_config.zone_name` or `dns_config.domain_name`) on a deployment that already exists.

### Why

The DNS authorization's `domain` is `ForceNew`, so it's replaced. The certificate's `create_before_destroy` applies to the authorization too, and the new one has the same name (`<name_prefix>-<default_branch>-dns-auth`), so creating it most likely fails with a name conflict. Nothing is deleted, but the apply fails.

### Proposed fix

To do:

1. Reproduce: change `domain_name` on a running deployment with manual DNS.
2. If it fails, document it in the README (deploy the new domain with a new `name_prefix`) or give the authorization a name that changes with the domain, which needs a migration for existing deployments.

## Remove the unused DNS authorizations

**Status:** to do in the next major version.

### Why

Since the wildcard certificate, only the default branch's DNS authorization is used. The others, one per branch and one for `www`, are still created, with their validation records, because 3.0 deployments have them. Deleting them in the same apply that replaces the certificate makes Terraform fail with a cycle: the map entry update waits for their deletion, which waits for the old certificate's deletion, which waits for the map entry update.

### Proposed fix

Create only the default branch's authorization and validation record, once deployments are past the certificate switch. No certificate changes in that apply, so no cycle. Check it with `terraform graph -type=apply -plan=<plan>` against a deployment that has more than one branch.

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
