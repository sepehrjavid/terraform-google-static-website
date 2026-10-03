# GCP Static Website Module

Terraform module that hosts a static website on GCP, with one environment per Git branch.

Each branch in `branches` gets its own public Cloud Storage bucket, served through a global HTTPS load balancer. The default branch is served at the domain itself and every other branch at `<branch>.<domain>`. Optionally, the module creates the Cloud DNS records and Cloud Build triggers that deploy each branch on push.

## What it creates

- **Per branch**: a bucket `<name_prefix>-<branch>-website-bucket` (public read, `index.html` as main and not-found page), a backend bucket (with Cloud CDN when `enable_cdn` is `true`) and a Certificate Manager DNS authorization.
- **Load balancer**: a global external Application Load Balancer (`EXTERNAL_MANAGED`) with a static IP, a Google-managed certificate covering all branch domains and, when `enable_http_redirect` is `true`, an HTTP to HTTPS redirect.
- **DNS** (when `dns_config.set_dns_config` is `true`): an A record for the domain, a CNAME for each branch subdomain and the certificate validation records.
- **CI/CD** (when `cicd.enable` is `true`): a Cloud Build GitHub connection (unless you pass an existing one), the linked repository and a push trigger per branch. Unless you pass `build_sa_ids`, each branch gets a build service account `<name_prefix>-<branch>-build` with `roles/storage.objectUser` on its bucket and `roles/logging.logWriter`.

The module enables the Certificate Manager API, and the Cloud Build and Secret Manager APIs when CI/CD is enabled.

## Requirements

- Terraform `>= 1.13` and the `hashicorp/google` provider `>= 7.0`.
- These APIs enabled on the project:
  - Compute Engine (`compute.googleapis.com`)
  - IAM (`iam.googleapis.com`), when the module creates the build service accounts
  - Cloud DNS (`dns.googleapis.com`), when `zone_name` is set
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

### Branch names

Branch names are used in resource names and DNS labels, so:

- they may only contain lowercase letters, digits and hyphens, must start with a letter and must not end with a hyphen;
- `<name_prefix>-<branch>-website-bucket` must be at most 63 characters;
- `<name_prefix>-<branch>-build` must be at most 30 characters when the module creates the build service accounts (CI/CD enabled without `build_sa_ids`).

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
| `build_sa_ids` | `map(string)` | `null` | Your own build service accounts, keyed by branch, as `projects/{project}/serviceAccounts/{email}`. Must have an entry for every branch. When set, the module creates no service accounts and grants no roles, so give them write access to the buckets and permission to write logs yourself. |

#### `github_config`

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `app_installation_id` | `string` | required | Installation ID of the Cloud Build GitHub App: the number at the end of the app's configuration page URL, e.g. `https://github.com/settings/installations/12345678`. |
| `access_token` | `string` | `null` | GitHub personal access token. The module stores it in Secret Manager as `<name_prefix>-github-access-token`. |
| `existing_token_secret_version_id` | `string` | `null` | A token already stored in Secret Manager, as `projects/{project}/secrets/{secret}/versions/{version}`. |

Set either `access_token` or `existing_token_secret_version_id`; if both are set, the existing secret is used. In both cases the module grants the Cloud Build service agent `roles/secretmanager.secretAccessor` on the secret. A value passed in `access_token` is stored in the Terraform state, so prefer `existing_token_secret_version_id` if that's a concern.

#### Build config

Each trigger runs `build_config_filename` from the pushed branch. The build must upload the site to that branch's bucket, `gs://<name_prefix>-<branch>-website-bucket`. The `$BRANCH_NAME` substitution gives the branch, and the `buckets` output lists the names.

Triggers run as a user-managed service account, so the build config must set where logs go, for example:

```yaml
options:
  logging: CLOUD_LOGGING_ONLY
```

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
| `dns_auth_creds` | Certificate validation records to create yourself, keyed by branch: record name (`cname`), `type` and value (`secret`). `null` when `set_dns_config` is `true`. |
| `buckets` | Bucket name per branch. |
| `github_connection_name` | Name of the Cloud Build GitHub connection in use. `null` when CI/CD is disabled. |
| `build_sa` | Build service accounts created by the module, keyed by branch. |

## DNS

The website domain is the apex of the DNS zone (or `domain_name` when no zone is given). If the apex is already in use, for example by another site at `example.com`, create a separate Cloud DNS zone for a subdomain such as `www.example.com`. Delegate it with NS records in the parent zone and pass that zone as `zone_name`. Branches are then served at `<branch>.www.example.com`.

There are two ways to set up the records:

- **Automated** (`set_dns_config = true`): the module creates all records in the zone given by `zone_name`.
- **Manual** (default): create these records with your DNS provider:
  - an `A` record for the domain, pointing to `lb_ip`;
  - for every other branch, a `CNAME` from `<branch>.<domain>` to the domain;
  - the certificate validation records from the `dns_auth_creds` output.

The certificate is issued once the validation records resolve, which can take a while. HTTPS requests fail until then.
