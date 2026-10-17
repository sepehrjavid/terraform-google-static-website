# GCP Static Website Module

Terraform module that hosts a static website on GCP, with one environment per Git branch.

Each branch in `branches` gets its own public Cloud Storage bucket, served through a global HTTPS load balancer. The default branch is served at the domain itself and every other branch at `<branch>.<domain>`. Optionally, the module creates the Cloud DNS records and Cloud Build triggers that deploy each branch on push.

## What it creates

- **Per branch**: a bucket `<name_prefix>-<branch>-website-bucket` (public read, `index.html` as main page and [`not_found_page`](#not_found_page) for paths that have no object), a backend bucket (with Cloud CDN when `enable_cdn` is `true`) and a Certificate Manager DNS authorization.
- **Load balancer**: a global external Application Load Balancer (`EXTERNAL_MANAGED`) with a static IP, a Google-managed certificate covering all branch domains and, when `enable_http_redirect` is `true`, an HTTP to HTTPS redirect. When `enable_www_redirect` is `true`, the certificate also covers `www.<domain>`, which redirects to the domain.
- **DNS** (when `dns_config.set_dns_config` is `true`): an A record for the domain, a CNAME for each branch subdomain (and for `www` when `enable_www_redirect` is `true`) and the certificate validation records.
- **CI/CD** (when `cicd.enable` is `true`): a Cloud Build GitHub connection (unless you pass an existing one), the linked repository and a push trigger per branch. Each branch gets a build service account `<name_prefix>-<branch>-build`, unless you pass your own in `build_sa_ids`. Either way, each branch's build service account gets `roles/storage.objectUser` on its bucket, `roles/logging.logWriter` and, when `enable_cdn` is `true`, a custom role that lets it invalidate the CDN cache (see [Build config](#build-config) and [Build service account roles](#build-service-account-roles)).

The module enables the Certificate Manager API, and the Cloud Build and Secret Manager APIs when CI/CD is enabled.

## Requirements

- Terraform `>= 1.13` and the `hashicorp/google` provider `>= 7.0`.
- These APIs enabled on the project:
  - Compute Engine (`compute.googleapis.com`)
  - IAM (`iam.googleapis.com`), when the module creates the build service accounts or, with CI/CD and `enable_cdn` both `true`, the CDN invalidation role
  - Cloud DNS (`dns.googleapis.com`), when `zone_name` is set
- When CI/CD and `enable_cdn` are both `true`, whoever runs Terraform needs permission to manage custom roles in the project, e.g. Role Administrator (`roles/iam.roleAdmin`). Custom roles are managed through the IAM API listed above.
- The project must allow public buckets: the `storage.publicAccessPrevention` and `iam.allowedPolicyMemberDomains` org policies must not block `allUsers`.
- A domain you control, at any registrar. For automated DNS, a Cloud DNS zone in `project_id` whose apex is the website domain (see [DNS](#dns)).
- For CI/CD with a new GitHub connection:
  - the [Cloud Build GitHub App](https://github.com/apps/google-cloud-build) installed on the repository
  - a GitHub personal access token (classic) with the `repo`, `read:user` and `read:org` scopes

## Usage

```hcl
module "website" {
  source = "github.com/sepehrjavid/terraform-google-static-website"

  project_id  = "my-project"
  region      = "europe-west1"
  name_prefix = "my-site"
  branches    = ["main", "develop"]

  dns_config = {
    set_dns_config = true
    zone_name      = "example-com" # Cloud DNS zone for example.com
  }

  cicd = {
    repo_uri = "https://github.com/example/my-site.git"
    github_config = {
      app_installation_id = "12345678"
      access_token        = var.github_token
    }
  }
}
```

This serves `main` at `https://example.com` and `develop` at `https://develop.example.com`.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project_id` | `string` | required | GCP project where all resources are created. |
| `region` | `string` | required | Region for the buckets and the Cloud Build connection, repository and triggers. |
| `name_prefix` | `string` | required | Prefix for all resource names. Use lowercase letters, digits and hyphens, starting with a letter. |
| `branches` | `set(string)` | required | Branches to deploy. See [Branch names](#branch-names). |
| `default_branch_name` | `string` | `"main"` | Branch served at the domain itself. Must be one of `branches`. |
| `dns_config` | `object` | required | Domain and DNS settings. See [`dns_config`](#dns_config). |
| `cicd` | `object` | required | CI/CD settings. Pass `{ enable = false }` to turn CI/CD off. See [`cicd`](#cicd). |
| `lb` | `object` | `{}` | Extra load balancer backends. See [`lb`](#lb). |
| `enable_cdn` | `bool` | `true` | Enable Cloud CDN on the bucket backends. |
| `enable_http_redirect` | `bool` | `true` | Redirect HTTP (port 80) to HTTPS. |
| `enable_www_redirect` | `bool` | `false` | Redirect `www.<domain>` to the domain with a 301, keeping the path and query. See [DNS](#dns). |
| `not_found_page` | `string` | `"index.html"` | Object served with status 404 for paths that have no object. Keep `"index.html"` for single-page apps; set `"404.html"` for multi-page sites. See [`not_found_page`](#not_found_page). |

### Branch names

Branch names are used in resource names and DNS labels, so:

- they may only contain lowercase letters, digits and hyphens, must start with a letter and must not end with a hyphen;
- `<name_prefix>-<branch>-website-bucket` must be at most 63 characters;
- `<name_prefix>-<branch>-build` must be at most 30 characters when the module creates the build service accounts (CI/CD enabled without `build_sa_ids`);
- no branch may be named `www` when `enable_www_redirect` is `true`.

### `not_found_page`

Cloud Storage serves this object when a path has neither an object nor an `index.html` under it, always with status 404.

- **Single-page apps** with client-side routing (Vue Router's `createWebHistory`, React Router's `BrowserRouter`, etc.): keep the default `index.html`, so routes such as `/about` load the app.
- **Multi-page sites** from static site generators (Hugo, Jekyll, Astro, Eleventy, Next.js static export): set `"404.html"`, and make sure the build uploads it to the bucket root.

> **Warning:** don't set `"404.html"` for a single-page app. Navigating inside the app still works, but opening or refreshing a route such as `/about` shows the 404 page instead of the app, or Cloud Storage's own error page if the build has no `404.html`.

Because the status is always 404, crawlers and uptime checks see a single-page app's deep links as 404s. Answering them with 200 would need a load balancer custom error response policy, which only works when the load balancer also has a backend service, not just backend buckets.

### `dns_config`

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `set_dns_config` | `bool` | `false` | Create the DNS records in Cloud DNS. Requires `zone_name`. |
| `zone_name` | `string` | `null` | Name of a Cloud DNS managed zone in `project_id`, e.g. `example-com`. The website domain is the zone's DNS name. |
| `domain_name` | `string` | `null` | Website domain, e.g. `example.com`. Required when `zone_name` isn't set. If both are set, they must match. |

### `cicd`

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `enable` | `bool` | `true` | Enable CI/CD. |
| `repo_uri` | `string` | `null` | GitHub repository URL, e.g. `https://github.com/owner/repo.git`. Required when `enable` is `true`. |
| `existing_gh_conn_name` | `string` | `null` | Name of an existing Cloud Build GitHub connection in `project_id` and `region`. When set, `github_config` is ignored. |
| `github_config` | `object` | `null` | Settings for a new GitHub connection. Required when `enable` is `true` and `existing_gh_conn_name` isn't set. |
| `build_config_filename` | `string` | `"cloudbuild.yaml"` | Path of the Cloud Build config file in the repository. |
| `build_sa_ids` | `map(string)` | `null` | Your own build service accounts, keyed by branch, as `projects/{project}/serviceAccounts/{email}`. Must have an entry for every branch. When set, the module creates no service accounts, but grants yours the same roles as its own (see [Build service account roles](#build-service-account-roles)). |

#### Build service account roles

Each branch's build service account, created by the module or passed in `build_sa_ids`, gets:

- `roles/storage.objectUser` on the branch's bucket;
- `roles/logging.logWriter` on the project;
- when `enable_cdn` is `true`, the CDN invalidation role on the project (see [Build config](#build-config)).

The module grants these one branch at a time. If several branches share a service account, removing one of them, or giving it another service account, revokes the shared project roles. The next `terraform apply` grants them again.

> **Warning:** the module adds the project roles with `google_project_iam_member`, which leaves the role's other members alone. If something else manages `roles/logging.logWriter` in this project authoritatively, with `google_project_iam_binding` or `google_project_iam_policy`, every apply of that configuration removes the build service accounts from the role, and the next apply of this module adds them back. Builds can't write logs in between. Add the build service accounts to that binding instead: your own from `build_sa_ids`, or the module's from the `build_sa` output. `google_project_iam_policy` also removes the CDN invalidation grant, and any other project role you don't list in it.

#### `github_config`

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `app_installation_id` | `string` | required | Installation ID of the Cloud Build GitHub App: the number at the end of the app's configuration page URL, e.g. `https://github.com/settings/installations/12345678`. |
| `access_token` | `string` | `null` | GitHub personal access token. The module stores it in Secret Manager as `<name_prefix>-github-access-token`. It's passed as a write-only argument, so it isn't saved in the Terraform state. |
| `access_token_version` | `number` | `1` | Increase this to store a new `access_token` in Secret Manager. Because the token is write-only, Terraform can't detect a changed token on its own. |
| `existing_token_secret_version_id` | `string` | `null` | A token already stored in Secret Manager, as `projects/{project}/secrets/{secret}/versions/{version}`. |

Set exactly one of `access_token` or `existing_token_secret_version_id`. In both cases the module grants the Cloud Build service agent `roles/secretmanager.secretAccessor` on the secret.

#### Build config

Each trigger runs `build_config_filename` from the pushed branch. The build must upload the site to that branch's bucket, `gs://<name_prefix>-<branch>-website-bucket`. Triggers run as a user-managed service account, so the build config must also set where logs go (`options.logging`).

Each trigger passes three substitutions to the build:

- `_WEBSITE_BUCKET`: the name of the branch's bucket (also in the `buckets` output).
- `_WEBSITE_URL_MAP`: the name of the load balancer's URL map (also the `url_map_name` output).
- `_WEBSITE_DOMAIN`: the branch's domain, e.g. `example.com` for the default branch and `develop.example.com` for `develop`. Use it where the site needs its own absolute URL, such as Hugo's `baseURL`.

If your build config defines substitutions with the same names, the trigger's values take precedence. A config that doesn't use them still works, because builds started by a trigger always allow unused substitutions (`ALLOW_LOOSE`).

Cloud Storage serves public objects that have no `Cache-Control` metadata with `public, max-age=3600`, and Cloud CDN caches them for that long. To make a new version live right away, set `Cache-Control` when you upload, then invalidate the URL map's cache. When `enable_cdn` is `true`, the build service accounts can do this: they get a custom role, `<name_prefix>_cdn_invalidator_<creation timestamp>` (hyphens become underscores), with only `compute.urlMaps.invalidateCache`. URL maps don't support IAM on the resource itself, so the role is granted on the project, which lets them invalidate the cache of any URL map in the project. Google lists `compute.urlMaps.invalidateCache` at the TESTING support level for custom roles (it may behave unexpectedly and isn't recommended for production); the predefined roles that include it, Load Balancer Admin and Network Admin, are much broader.

For a site that `npm run build` writes to `dist/`:

```yaml
steps:
  - name: node:24
    entrypoint: npm
    args: [ci]
  - name: node:24
    entrypoint: npm
    args: [run, build]
  - name: gcr.io/google.com/cloudsdktool/google-cloud-cli:stable
    entrypoint: bash
    args:
      - -c
      - |
        set -euo pipefail
        # Fingerprinted files (dist/assets with Vite) never change, so caches can keep them.
        gcloud storage cp --recursive dist/assets gs://$_WEBSITE_BUCKET --cache-control="public, max-age=31536000, immutable"
        # Everything else, HTML included, is revalidated on every request.
        rm -r dist/assets
        gcloud storage cp --recursive dist/* gs://$_WEBSITE_BUCKET --cache-control=no-cache
        gcloud compute url-maps invalidate-cdn-cache $_WEBSITE_URL_MAP --path="/*" --async
options:
  logging: CLOUD_LOGGING_ONLY
```

- Cloud Build replaces `$_WEBSITE_BUCKET` and `$_WEBSITE_URL_MAP` before bash runs. A shell variable of your own would need `$$`.
- Fingerprinted files are uploaded first, so new pages never point to missing files. Files removed from the site stay in the bucket. `gcloud storage rsync --delete-unmatched-destination-objects` would delete them, but syncing to a bucket root needs `storage.buckets.get`, which `roles/storage.objectUser` doesn't include.
- `--async` returns once the invalidation is accepted. It takes effect in about 10 seconds. Without `--async`, gcloud waits for the operation, which also needs `compute.globalOperations.get` and `compute.urlMaps.get`.
- The invalidation applies to every branch's domain. Add `--host` to limit it to one.
- Without CDN, drop the invalidation step (the build service accounts don't get the role then), but keep setting `Cache-Control`: browsers cache too.

### `lb`

`lb.extra_backends` routes a path prefix on a branch's domain to another backend, such as an API. It's a map keyed by branch name, with one backend per branch.

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `url_prefix` | `string` | required | Path prefix without slashes, e.g. `api`. Requests to `/api` and `/api/*` go to the backend. |
| `backend_id` | `string` | required | ID of a global backend service or backend bucket. Backend services must use the `EXTERNAL_MANAGED` load balancing scheme. |
| `strip_prefix` | `bool` | `true` | Remove the prefix before forwarding, so `/api/users` reaches the backend as `/users`. |

```hcl
lb = {
  extra_backends = {
    main = {
      url_prefix = "api"
      backend_id = "projects/my-project/global/backendServices/api"
    }
  }
}
```

## Outputs

| Name | Description |
|------|-------------|
| `lb_ip` | Load balancer IP address. |
| `dns_auth_creds` | Certificate validation records to create yourself, keyed by branch (plus `www` when `enable_www_redirect` is `true`): record name (`cname`), `type` and value (`secret`). `null` when `set_dns_config` is `true`. |
| `buckets` | Bucket name per branch. |
| `github_connection_name` | Name of the Cloud Build GitHub connection in use. `null` when CI/CD is disabled. |
| `build_sa` | Build service accounts created by the module, keyed by branch. |
| `url_map_name` | Name of the HTTPS load balancer's URL map, `<name_prefix>-https-lb`. Pass it to `gcloud compute url-maps invalidate-cdn-cache`. |

## DNS

The website domain is the apex of the DNS zone (or `domain_name` when no zone is given). If the apex is already in use, for example by another site at `example.com`, create a separate Cloud DNS zone for a subdomain such as `www.example.com`. Delegate it with NS records in the parent zone and pass that zone as `zone_name`. Branches are then served at `<branch>.www.example.com`.

With `enable_www_redirect = true`, requests to `https://www.<domain>/<path>?<query>` get a 301 to `https://<domain>/<path>?<query>`, and `http://www.<domain>` is first redirected to HTTPS. The certificate gets `www.<domain>` with its own DNS authorization. This is meant for an apex domain such as `example.com`: with a delegated zone such as `www.example.com`, it would redirect `www.www.example.com`.

There are two ways to set up the records:

- **Automated** (`set_dns_config = true`): the module creates all records in the zone given by `zone_name`. With `enable_www_redirect`, the zone must not already have a `www` record.
- **Manual** (default): create these records with your DNS provider:
  - an `A` record for the domain, pointing to `lb_ip`;
  - for every other branch, a `CNAME` from `<branch>.<domain>` to the domain;
  - with `enable_www_redirect`, a `CNAME` from `www.<domain>` to the domain;
  - the certificate validation records from the `dns_auth_creds` output.

The certificate is issued once the validation records resolve, which can take a while. HTTPS requests fail until then.
