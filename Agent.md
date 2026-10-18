# Agent instructions

How to write code in this repo. Also follow the conventions and checks in [CLAUDE.md](CLAUDE.md).

## Keep users away from security mistakes

Design decisions must steer users, including those who don't know the risks, away from insecure setups.

- Secure by default: grant the least privilege needed, and keep environments (branches) isolated, e.g. one service account per branch, so one environment can't affect another.
- Don't add options that make an insecure setup easy, even when they're convenient. Where the module can detect an unsafe input, reject it in `variables.tf` with a message that explains the risk. Where it can't, warn in the README.
- When security and convenience or simplicity conflict, choose security, and explain the trade-off in the PR.

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
