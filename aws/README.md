# AWS CI/CD learning environment

This directory contains Phase 1 of an AWS CI/CD learning exercise. It creates
one manually triggered AWS CodeBuild project for the public Family Control
GitHub repository.

Phase 1 deliberately does not create CodePipeline, webhooks, an S3 artifact
bucket, a VPC, a NAT Gateway, persistent build capacity, or access from AWS to
the home router.

## What it creates

- one AWS CodeConnections GitHub App connection;
- one small, on-demand CodeBuild project;
- one least-privilege CodeBuild service role; and
- one CloudWatch log group with 14-day retention.

The build runs the same lint, SBOM, ShellCheck, ucode, ubus, UCI, Docker, and
firewall4 checks as the existing GitHub workflow. Docker requires CodeBuild
privileged mode. The project has no deployment credentials.

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
select `familycontrol-ci-github`, choose **Update pending connection**, and
authorize the GitHub App for this repository.

After authorization, create the remaining Phase 1 resources:

```sh
tofu -chdir=aws/tofu apply
```

Review the plan carefully before approving either operation. Targeted apply is
used only to cross the connection's mandatory one-time authorization boundary.

## Run the build

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

CloudWatch retains build logs for 14 days. There is no automatic trigger in
Phase 1, so builds consume minutes only when deliberately started.

## Remove the environment

```sh
tofu -chdir=aws/tofu destroy
```

After destruction, confirm that the GitHub connection and CodeBuild project no
longer appear in the AWS console. Review **GitHub → Settings → Applications**
and revoke the AWS Connector for GitHub installation if it is no longer used
by any AWS project.
