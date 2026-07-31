# AWS CI/CD learning environment

This directory contains the first two phases of an AWS CI/CD learning exercise
for the public Family Control GitHub repository:

1. a manually triggered CodeBuild project; and
2. a V2 CodePipeline using the GitHub connection's native push detection for
   the configured branch (`main` by default).

Neither phase creates a VPC, NAT Gateway, persistent build capacity, release
deployment, or access from AWS to the home router.

## What it creates

- one AWS CodeConnections GitHub App connection;
- one manual and four focused pipeline-fed, on-demand CodeBuild projects;
- one least-privilege CodeBuild service role; and
- one CloudWatch log group with 14-day retention;
- one V2 CodePipeline; and
- one private, encrypted, versioned artifact bucket whose objects expire after
  seven days.

The build runs the same lint, SBOM, ShellCheck, ucode, ubus, UCI, Docker, and
firewall4 rule-rendering checks as the existing GitHub workflow. Docker
requires CodeBuild privileged mode. CodeBuild's host kernel does not provide
the nftables NAT modules needed by `nft --check`, so that final kernel-level
assertion is skipped only in CodeBuild; it remains enabled in GitHub Actions
and local CI. The project has no deployment credentials.

## Validation dependency graph

The automatic pipeline deliberately separates failure domains:

```text
GitHub Source
   |-- JavaScriptLint ----- npm ci, ESLint
   |-- SBOM --------------- regenerate and compare CycloneDX SBOM
   |-- ShellCheck ---------- lint maintained shell scripts
   `-- OpenWrtIntegration -- ucode, ubus, UCI and firewall tests
             |
        Validate stage
```

All four validation actions depend on the GitHub source action. They have no
dependencies on one another and use the same CodePipeline run order, so AWS
can run them in parallel. The Validate stage is the join: one failed action
fails the stage and pipeline, while each action has its own build status and
CloudWatch log stream.

Only `OpenWrtIntegration` has Docker privileged mode. JavaScript, SBOM and
ShellCheck builds run without it. The separate jobs intentionally repeat a
small amount of environment startup work in exchange for clearer failures and
independent execution.

The manually triggered Phase 1 project remains an all-in-one build for a quick
complete diagnostic. It is not used by the automatic pipeline.

## Prerequisites

- OpenTofu 1.9 or later;
- AWS CLI v2;
- an AWS identity able to manage CodeBuild, CodeConnections, IAM roles and
  CloudWatch log groups; and
- repository-owner permission for `tropikhajma/parentalcontrol`.

Use a short-lived AWS IAM Identity Center session or another temporary
credential mechanism. Do not create or commit a long-lived IAM access key.

Confirm the intended account before creating anything:

```sh
export AWS_PROFILE=AdministratorAccess-174516978701
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
```

`AWS_PROFILE` is inherited by OpenTofu through the AWS SDK credential chain,
so it must remain set in the terminal used for `tofu plan` and `tofu apply`.
Alternatively, prefix an individual command with
`AWS_PROFILE=AdministratorAccess-174516978701`.

The expected account is `174516978701`. Stop if `get-caller-identity` reports
another account. The OpenTofu configuration's default region is
`eu-central-1`, independently of the CLI profile's default region.

## Validate locally

```sh
tofu -chdir=aws/tofu init -backend=false
tofu -chdir=aws/tofu fmt -check
tofu -chdir=aws/tofu validate
```

The local state backend is intentional for this single-user learning phase.
State files and local plans are ignored by Git. A remote state backend should
be introduced before sharing management of these resources.

## Create and authorize the GitHub connection

Creating a connection through OpenTofu leaves it in `PENDING` state. First
create only the connection:

```sh
tofu -chdir=aws/tofu apply \
  -target=aws_codestarconnections_connection.github
```

Then open **AWS Developer Tools → Settings → Connections** in `eu-central-1`,
select `familycontrol-ci-github-v2`, and choose **Update pending connection**.
During the GitHub flow, install the AWS Connector for GitHub App on the account
that owns the repository and grant it access to `parentalcontrol`. Merely
listing the App under **Authorized GitHub Apps** is insufficient: it must also
appear under **Installed GitHub Apps** so GitHub delivers push events.

After authorization, create the remaining resources:

```sh
tofu -chdir=aws/tofu apply
```

Review the plan carefully before approving either operation. Targeted apply is
used only to cross the connection's mandatory one-time authorization boundary.

## Run the manual Phase 1 build

```sh
aws codebuild start-build \
  --region eu-central-1 \
  --project-name familycontrol-ci
```

The response contains a build ID. Follow it in the CodeBuild console or query:

```sh
aws codebuild batch-get-builds \
  --region eu-central-1 \
  --ids BUILD_ID
```

CloudWatch retains build logs for 14 days. The manual project consumes minutes
only when deliberately started.

## Use the Phase 2 pipeline

The `familycontrol-ci` V2 pipeline uses the GitHub connection's native change
detection for its configured source branch (`main` by default). Its source
action uses `CODEBUILD_CLONE_REF`, so CodeBuild receives Git history and
`npm run sbom:check` can detect a stale checked-in SBOM.

Inspect recent executions:

```sh
aws codepipeline list-pipeline-executions \
  --region eu-central-1 \
  --pipeline-name familycontrol-ci \
  --max-results 5
```

Start an execution without making a commit:

```sh
aws codepipeline start-pipeline-execution \
  --region eu-central-1 \
  --name familycontrol-ci
```

The S3 bucket exists only for internal pipeline source artifacts. It blocks all
public access, enforces TLS, uses S3-managed encryption and versioning, and
expires current and noncurrent objects after seven days. `force_destroy` is
enabled so the learning environment can be removed with one OpenTofu destroy.

The manual CodeBuild project remains available while Phase 2 is evaluated. It
can be removed later if the parallel pipeline fully replaces it.

V2 pipelines are billed by action-execution minute. AWS currently provides 100
free V2 action-execution minutes per account per month. Splitting validation
into four actions improves diagnostics but consumes more action minutes per
push, so monitor usage before adding pull-request triggers or more stages.

## Remove the environment

```sh
tofu -chdir=aws/tofu destroy
```

After destruction, confirm that the GitHub connection and CodeBuild project no
longer appear in the AWS console. Review **GitHub → Settings → Applications**
and revoke the AWS Connector for GitHub installation if it is no longer used
by any AWS project.
