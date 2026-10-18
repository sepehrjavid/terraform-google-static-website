# Agent instructions

How to write code in this repo. Also follow the conventions and checks in [CLAUDE.md](CLAUDE.md).

## Keep it simple

- Write the simplest Terraform that works. Don't add variables, locals, resources or abstractions that aren't needed.
- Avoid duplication. If the same expression or block is needed in more than one place, reuse it (a local, `for_each`, a `dynamic` block) instead of copying it.

## Comments

- Only add a comment when it's really needed: the code can't explain itself (e.g. a non-obvious GCP constraint or ordering requirement), or you're leaving a warning or a TODO for that section.
- Keep comments short. Don't explain what the code already says.

## Verify every resource and field

Before adding or changing Terraform code, check every resource, argument and attribute you use against:

- the Terraform Google provider docs: https://registry.terraform.io/providers/hashicorp/google/latest/docs
- the Google Cloud docs for the service.

Confirm that the resource and its fields exist, their names, ID formats and naming limits, and which changes force replacement. `terraform providers schema -json` (after `terraform init -backend=false`) shows the installed provider's exact schema. Don't assume a field or resource exists.

## Ask when unsure

If something is unclear, such as the requirements, the expected behaviour or which option to pick, ask instead of making assumptions.
