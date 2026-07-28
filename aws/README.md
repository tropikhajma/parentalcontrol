# AWS CI/CD learning environment

This directory contains the first two phases of an AWS CI/CD learning exercise
for the public Family Control GitHub repository:

1. a manually triggered CodeBuild project; and
2. a V2 CodePipeline with an explicit push trigger for `main`.

Neither phase creates a VPC, NAT Gateway, persistent build capacity, release
deployment, or access from AWS to the home router.

## What it creates

- one AWS CodeConnections GitHub App connection;
- one manual and one pipeline-fed small, on-demand CodeBuild project;
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

The `familycontrol-ci` V2 pipeline has an explicit Git push trigger filtered to
`main`. Its source action uses `CODEBUILD_CLONE_REF`, so CodeBuild receives Git
history and `npm run sbom:check` can detect a stale checked-in SBOM.

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
can be removed later if the pipeline fully replaces it.

V2 pipelines are billed by action-execution minute. AWS currently provides 100
free V2 action-execution minutes per account per month. This pipeline has only
Source and Validate actions; monitor usage before adding pull-request triggers
or more stages.

## Remove the environment

```sh
tofu -chdir=aws/tofu destroy
```

After destruction, confirm that the GitHub connection and CodeBuild project no
longer appear in the AWS console. Review **GitHub → Settings → Applications**
and revoke the AWS Connector for GitHub installation if it is no longer used
by any AWS project.
