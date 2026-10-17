# Basic example

A single website at `https://<domain>`, served from one bucket through an HTTPS load balancer with a Google-managed certificate. The domain's DNS can be hosted by any provider, and there's no CI/CD: you upload the site yourself.

It creates the `main` branch's bucket, a backend bucket with Cloud CDN, the load balancer with its static IP and an HTTP to HTTPS redirect, and the certificate with its DNS authorization.

## Before you start

- The Compute Engine API (`compute.googleapis.com`) is enabled on the project. The module enables the Certificate Manager API itself.
- The project allows public buckets (see the module's [Requirements](../../README.md#requirements)).
- You can create DNS records for the domain.

## Deploy

```sh
terraform init
terraform apply -var project_id=my-project -var name_prefix=my-site -var domain=example.com
```

`name_prefix` is part of the bucket name, `<name_prefix>-main-website-bucket`, which must be unique across all of Cloud Storage.

## Create the DNS records

At your DNS provider, create:

| Name | Type | Value |
|------|------|-------|
| the domain, e.g. `example.com` | `A` | the `lb_ip` output |
| `cname` from the `dns_auth_creds` output, e.g. `_acme-challenge.example.com.` | `CNAME` | `secret` from the `dns_auth_creds` output, e.g. `0e40fc77-...authorize.certificatemanager.goog.` |

```sh
terraform output lb_ip
terraform output dns_auth_creds
```

Many providers want the record name without the domain, e.g. `_acme-challenge`. The validation `CNAME` must be the only record with that name.

Google issues the certificate once the validation record resolves, which can take a while. Until then, HTTPS requests fail.

## Upload the site

Copy the built site (here `public/`, with `index.html` at its root) to the bucket from the `buckets` output:

```sh
gcloud storage cp --recursive ./public/* gs://my-site-main-website-bucket --cache-control=no-cache
```

Without `--cache-control`, Cloud Storage serves objects with `public, max-age=3600`, so browsers and Cloud CDN can keep showing the old version for an hour. With `no-cache`, they check for a new version on every request. Files you delete from the site stay in the bucket until you remove them with `gcloud storage rm`.

To deploy on every push instead, see the [Cloud Build example](../cloud-build).
