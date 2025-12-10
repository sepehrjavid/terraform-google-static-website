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
| `branches`            | `set(string)`   | Set of branch names that need deployment.                                                     | `null`       | `[ "main", "develop" ]`                   |
| `name_prefix`         | `string`          | Name prefix used to distinguish resource.                                                      | `null`       | `"my-test"`                                     | 
| `cicd`         | `object`          | CI/CD config for automated deployments.                                                      | `null`       | See structure below                                       |
| `enable_cdn`         | `bool`          | Enables Cloud CDN for better performance.                                                     | `true`       | `true`                                       |
| `lb`         | `object`          | Configuration for extra load balancer backends.                                                      | `{}`       | See structure below.                           |
| `enable_http_redirect`| `bool`          | Enables HTTP to HTTPS redirection.                                                            | `true`       | `true`                                       |
| `default_branch_name` | `string`        | The name of the default production branch.                                                   | `"main"`       | `"main"`                                    |
| `dns_config`         | `object`        | Configuration for DNS settings.                                                              | `null`       | See structure below.                           |



**Note: The varibales with default value of `null` are required.**

### CI/CD Configuration Object Structure

`cicd` object consists of the following variables:

| Variable               | Type            | Description                                                                                      | Default       | Example                                      |
|------------------------|----------------|------------------------------------------------------------------------------------------------|---------------|----------------------------------------------|
| `enable`            | `bool`   | Whether to enable CI/CD                                                     | `true`       | `false`                   |
| `existing_gh_conn_name`       | `string`        | The name of an existing github connection in CloudBuild                                                                 | `null`       | `my_connection`                           |
| `repo_uri`         | `string`          | Repository URI                                                       | `null`       | `https://github.com/my_repo.git`                                       |
| `build_config_filename`         | `string`          | The name of the Cloud Build config file.                                                       | `cloudbuild.yaml`       | `build.yaml` 
| `build_sa_ids`         | `map(string)`          | A map of service account IDs for Cloud Build, keyed by branch name. If not provided, a service account is created.                                                       | `null`       | `{"main" = "sa-main@p.iam.gserviceaccount.com"}` 
| `github_config`         | `object`          | GitHub configuration details.                                                       | `null`       | See structure below  


**Note: Either `existing_gh_conn_name` or `github_config` must be provided when `enable` is `true`.**

**Note: When `enable` is set to `true`, `repo_uri` must be provided. Otherwise can be left undefined**

**Note: If `build_sa_ids` is provided, it must contain an entry for each branch defined in the `branches` variable.**

### GitHub Configuration Object Structure

`github_config` object consists of the following variables:

| Variable               | Type            | Description                                                                                      | Default       | Example                                      |
|------------------------|----------------|------------------------------------------------------------------------------------------------|---------------|----------------------------------------------|
| `access_token`            | `string`   | GitHub access token                                                     | `null`       | `ghp_************************************`                   |
| `existing_token_secret_version_id`            | `string`   | Existing Secret Manager version ID where the GitHub token is stored.                                                     | `null`       | `projects/123/secrets/my-secret/versions/1`                  |
| `app_installation_id`       | `string`        | GitHub App installation                                                                 | `null`       | `12345678`                           |

**Note: When `github_config` is provided, either `access_token` or `existing_token_secret_version_id` must have a value.**

### Load Balancer Configuration Object Structure

`lb` object consists of the following variables:

| Variable               | Type            | Description                                                                                      | Default       | Example                                      |
|------------------------|----------------|------------------------------------------------------------------------------------------------|---------------|----------------------------------------------|
| `extra_backends`            | `map(object)`   |  A map of extra backend services, keyed by branch name.                                                     | `null`       | See below                   |

The `extra_backends` map value is an object with the following attributes:

| Attribute               | Type            | Description                                                                                      | Default       |
|------------------------|----------------|------------------------------------------------------------------------------------------------|---------------|
| `url_prefix`            | `string`   |  The URL prefix for which this backend should be used.                                                     | (required)       |
| `backend_id`       | `string`        |  The ID of the backend service or backend bucket.                                                                 | (required)       |
| `strip_prefix`         | `bool`          | If true, the `url_prefix` is stripped before forwarding the request to the backend.                                                       | `true`       |

### DNS Configuration Object Structure

`dns_config` object consists of the following variables:

| Variable               | Type            | Description                                                                                      | Default       | Example                                      |
|------------------------|----------------|------------------------------------------------------------------------------------------------|---------------|----------------------------------------------|
| `set_dns_config`            | `bool`   |  Whether to configure DNS settings.                                                     | `false`       | `true`                   |
| `zone_name`       | `string`        |  DNS Zone Name (If created in GCP) (Required if `set_dns_config` is true).                                                                 | `null`       | `example-com`                           |
| `domain_name`         | `string`          | Domain Name for the website.                                                       | `null`       | `example.com`                                       |


**Note:**
- If `set_dns_config` is `true`, `zone_name` must be provided.
- At all times either `domain_name` or `set_dns_config` must be specified. (the domain name is derived from the zone when `domain_name` is not provided.)

### Example Values

```hcl
branches = ["main", "develop"]

cicd = {
  enable                = true
  repo_uri              = "https://github.com/example/app"
  build_config_filename = "mycloudbuild.yaml"
  github_config = {
    access_token                     = "ghp_abcdef1234567890"
    app_installation_id              = "1234567"
    repo_uri                         = "https://github.com/example/app"
  }
}

lb = {
  extra_backends = {
    main = {
      url_prefix   = "api"
      backend_id   = "backend_id"
      strip_prefix = false
    }
  }
}

enable_cdn = true
enable_http_redirect = true
default_branch_name = "main"

dns_config = {
  set_dns_config = true
  zone_name      = "example-zone" # example.com
}
```

### More on DNS

The `dns_config` block controls DNS settings.  The `set_dns_config` variable determines the configuration method:

- Manual DNS (`set_dns_config` = `false` - Default): The module outputs the website's IP address and DNS challenge records for TLS verification. You are responsible for creating the necessary DNS records with your provider.
- Automated DNS (`set_dns_config` = `true`): Provide the `zone_name` of your Cloud DNS zone. The module automatically creates all required DNS records, including those for TLS certificate verification.

TLS certificate verification may take some time.
