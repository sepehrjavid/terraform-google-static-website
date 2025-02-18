# GCP Static Website Module

This Terraform module helps you deploy a static website on GCP seamlessly.

## Prerequisites

Before you begin, ensure the following:

1. You have a static website project hosted on GitHub.
2. You have access to a GCP account with a user having sufficient permissions.
3. A registered domain. The registrar does not have to be GCP however, preferred.


## Input Variables

You can configure the module using the following variables:

| Variable               | Type            | Description                                                                                      | Default       | Example                                      |
|------------------------|----------------|------------------------------------------------------------------------------------------------|---------------|----------------------------------------------|
| `branches`            | `set(string)`   | Set of branch names that need deployment.                                                     | None       | `[ "main", "develop" ]`                   |
| `cicd`         | `object`          | CI/CD config for automated deployments.                                                      | None       | See structure below                                       |
| `enable_cdn`         | `bool`          | Enables Cloud CDN for better performance.                                                     | `true`       | `true`                                       |
| `enable_http_redirect`| `bool`          | Enables HTTP to HTTPS redirection.                                                            | `true`       | `true`                                       |
| `default_branch_name` | `string`        | The name of the default production branch.                                                   | `"main"`       | `"main"`                                    |
| `dns_config`         | `object`        | Configuration for DNS settings.                                                              | None       | See structure below.                           |



**Note: The varibales with default value of `None` are required.**

### CI/CD Configuration Object Structure

`cicd` object consists of the following variables:

| Variable               | Type            | Description                                                                                      | Default       | Example                                      |
|------------------------|----------------|------------------------------------------------------------------------------------------------|---------------|----------------------------------------------|
| `enable`            | `bool`   | Whether to enable CI/CD                                                     | `true`       | `false`                   |
| `existing_gh_conn_name`       | `string`        | The name of an existing github connection in CloudBuild                                                                 | None       | `my_connection`                           |
| `github_config`         | `object`          | GitHub configuration details.                                                       | None       | See structure below  


**Note: `github_config` is only required if `enable` is  `true`**

### GitHub Configuration Object Structure

`github_config` object consists of the following variables:

| Variable               | Type            | Description                                                                                      | Default       | Example                                      |
|------------------------|----------------|------------------------------------------------------------------------------------------------|---------------|----------------------------------------------|
| `access_token`            | `string`   | GitHub access token                                                     | None       | `ghp_************************************`                   |
| `app_installation_id`       | `string`        | GitHub App installation                                                                 | None       | `https://github.com/my_repo.git`                           |
| `repo_uri`         | `string`          | Repository URI                                                       | None       | `12345678`                                       |


### DNS Configuration Object Structure

`dns_config` object consists of the following variables:

| Variable               | Type            | Description                                                                                      | Default       | Example                                      |
|------------------------|----------------|------------------------------------------------------------------------------------------------|---------------|----------------------------------------------|
| `set_dns_config`            | `bool`   |  Whether to configure DNS settings.                                                     | `false`       | `true`                   |
| `zone_name`       | `string`        |  DNS Zone Name (If created in GCP) (Required if `set_dns_config` is true).                                                                 | None       | `example-com`                           |
| `domain_name`         | `string`          | Domain Name for the website.                                                       | None       | `example.com`                                       |

### Example Values

```hcl
branches = ["main", "develop"]

cicd = {
  enable = true
  github_config = {
    access_token        = "ghp_abcdef1234567890"
    app_installation_id = "1234567"
    repo_uri            = "https://github.com/example/app"
  }
}

enable_cdn = true
enable_http_redirect = true
default_branch_name = "main"

dns_config = {
  set_dns_config = true
  zone_name      = "example-zone"
  domain_name    = "example.com"
}
```

### More on DNS

The `dns_config` block controls DNS settings.  The `set_dns_config` variable determines the configuration method:

- Manual DNS (`set_dns_config` = `false` - Default): The module outputs the website's IP address and DNS challenge records for TLS verification. You are responsible for creating the necessary DNS records with your provider.
- Automated DNS (`set_dns_config` = `true`): Provide the `zone_name` of your Cloud DNS zone. The module automatically creates all required DNS records, including those for TLS certificate verification.

TLS certificate verification may take some time.

