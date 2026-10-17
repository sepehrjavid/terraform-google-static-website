# Cloud Build example

Serves the `main` branch at `https://<domain>` and `develop` at `https://develop.<domain>`, where the domain is the DNS name of a Cloud DNS zone. Every push to either branch runs Cloud Build, which builds the site and uploads it to that branch's bucket.

It creates a bucket, a CDN-enabled backend bucket, a trigger and a build service account per branch, the HTTPS load balancer and certificate, the DNS records in the zone, and a Cloud Build GitHub connection with the token stored in Secret Manager.

## Before you start

- These APIs are enabled on the project: Compute Engine (`compute.googleapis.com`), IAM (`iam.googleapis.com`) and Cloud DNS (`dns.googleapis.com`). The module enables Certificate Manager, Cloud Build and Secret Manager itself.
- The project has a Cloud DNS zone whose DNS name is the domain, and your registrar delegates the domain to the zone's name servers.
- You can manage custom roles in the project, e.g. with Role Administrator (`roles/iam.roleAdmin`). The module creates one that lets the builds invalidate the CDN cache.
- The project allows public buckets (see the module's [Requirements](../../README.md#requirements)).
- The [Cloud Build GitHub App](https://github.com/apps/google-cloud-build) is installed on the site's repository. Its installation ID is the number at the end of the app's configuration page URL.
- You have a GitHub personal access token (classic) with the `repo`, `read:user` and `read:org` scopes.

## Deploy

```sh
read -rs TF_VAR_github_token && export TF_VAR_github_token # paste the token
terraform init
terraform apply \
  -var project_id=my-project \
  -var name_prefix=my-site \
  -var zone_name=example-com \
  -var repo_uri=https://github.com/owner/site.git \
  -var app_installation_id=12345678
```

The module stores the token in Secret Manager as a write-only value, so it isn't saved in the Terraform state.

The module also creates the certificate validation records. Google issues the certificate once they resolve, which can take a while. Until then, HTTPS requests fail.

## Add a build config to the site

Each trigger runs `cloudbuild.yaml` from the pushed branch of the site's repository. Copy the config for your framework into the root of the site's repository as `cloudbuild.yaml`:

| Config | Builds | Output |
|--------|--------|--------|
| [`vite.cloudbuild.yaml`](build-configs/vite.cloudbuild.yaml) | `npm ci && npm run build` | `dist/` |
| [`hugo.cloudbuild.yaml`](build-configs/hugo.cloudbuild.yaml) | `hugo --minify --baseURL https://$_WEBSITE_DOMAIN/` | `public/` |
| [`nextjs.cloudbuild.yaml`](build-configs/nextjs.cloudbuild.yaml) | `npm ci && npm run build` with `output: 'export'` | `out/` |

To keep the file's name or put it elsewhere, set `build_config_filename` in `cicd` to its path in the repository, e.g. `build_config_filename = "hugo.cloudbuild.yaml"`.

Each config uploads the site to its branch's bucket, `$_WEBSITE_BUCKET`. The Vite and Next.js configs give fingerprinted files a one-year `Cache-Control` and everything else `no-cache`; the Hugo config uploads everything with `no-cache`. Then each config invalidates the CDN cache of `$_WEBSITE_URL_MAP`. If you set `enable_cdn = false`, remove that last step. See [Build config](../../README.md#build-config) for the substitutions the triggers pass and why the configs upload this way.

Framework notes:

- **Hugo**: `baseURL` is the branch's own domain (`$_WEBSITE_DOMAIN`), so links and the sitemap on `develop` point to `develop.<domain>`. The config checks out git submodules, where themes often live. They must be public: the build has no credentials for private ones.
- **Next.js**: the site's `next.config.js` needs `output: 'export'` and `trailingSlash: true`. The comment at the top of the config explains why.
- Hugo and Next.js write a `404.html`. Set `not_found_page = "404.html"` on the module so missing pages return it.

## Deploy the site

Push to `main` or `develop`. To build a branch without pushing, run its trigger, named `<name_prefix>-<branch>`:

```sh
gcloud builds triggers run my-site-main --region=us-central1 --branch=main
```

## Outputs

- `buckets`: each branch's bucket, if you want to look at or upload files by hand.
- `url_map_name`: the URL map whose cache the configs invalidate, for `gcloud compute url-maps invalidate-cdn-cache`.
- `build_sa`: the service account each branch's builds run as. Grant it more roles if your build needs them, e.g. to read a secret.
- `github_connection_name`: pass it as `cicd.existing_gh_conn_name` to reuse the connection for another site in the same project and region.
