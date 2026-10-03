# CLAUDE.md

Terraform module that deploys a static website on GCP (buckets, HTTPS load balancer, Certificate Manager, Cloud DNS, Cloud Build CI/CD).

## Guidelines

- Prefer the simplest solution that works. Don't add abstraction, variables or resources that aren't needed.
- Only add comments when the code can't explain itself (e.g. a non-obvious GCP constraint or ordering requirement).
- Before adding or changing a resource, check the Terraform Google provider docs (registry.terraform.io/providers/hashicorp/google) and the GCP docs for the service. Confirm argument names, ID formats, naming limits and which changes force replacement.

## Conventions

- Every resource that accepts it sets `project = var.project_id`. Regional resources use `location = var.region`.
- Resource names start with `var.name_prefix` so multiple instances can share a project.
- Validate inputs in `variables.tf` so mistakes fail at plan time with a clear message.
- Keep `README.md` in sync when adding or changing input variables.

## Checks

Run before finishing a change:

```sh
terraform fmt -check
terraform init -backend=false && terraform validate
```
