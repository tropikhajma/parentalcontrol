# SPDX-License-Identifier: GPL-3.0-or-later

locals {
  github_repository_id = trimprefix(
    trimsuffix(var.github_repository_url, ".git"),
    "https://github.com/"
  )

  pipeline_validation_jobs = {
    javascript = {
      display_name = "JavaScriptLint"
      description  = "Install JavaScript dependencies and run ESLint"
      buildspec    = "aws/buildspec-javascript.yml"
      privileged   = false
    }
    sbom = {
      display_name = "SBOM"
      description  = "Verify that the checked-in CycloneDX SBOM is current"
      buildspec    = "aws/buildspec-sbom.yml"
      privileged   = false
    }
    shellcheck = {
      display_name = "ShellCheck"
      description  = "Lint all maintained shell scripts"
      buildspec    = "aws/buildspec-shellcheck.yml"
      privileged   = false
    }
    openwrt = {
      display_name = "OpenWrtIntegration"
      description  = "Run ucode, ubus, UCI and firewall integration checks"
      buildspec    = "aws/buildspec-openwrt.yml"
      privileged   = true
    }
  }
}

resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket        = "${var.project_name}-artifacts-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_versioning" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  rule {
    id     = "expire-pipeline-artifacts"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.pipeline_artifacts]
}

resource "aws_s3_bucket_policy" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.pipeline_artifacts.arn,
        "${aws_s3_bucket.pipeline_artifacts.arn}/*"
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.pipeline_artifacts]
}

resource "aws_codebuild_project" "pipeline_validation" {
  for_each = local.pipeline_validation_jobs

  name          = "${var.project_name}-${each.key}"
  description   = each.value.description
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 15

  artifacts {
    type = "CODEPIPELINE"
  }

  dynamic "cache" {
    for_each = each.value.privileged ? [true] : []
    content {
      type  = "LOCAL"
      modes = ["LOCAL_DOCKER_LAYER_CACHE"]
    }
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = each.value.privileged
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = each.key
      status      = "ENABLED"
    }

    s3_logs {
      status = "DISABLED"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = each.value.buildspec
  }

  depends_on = [aws_iam_role_policy.codebuild]
}

resource "aws_iam_role" "codepipeline" {
  name = "${var.project_name}-codepipeline"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "${var.project_name}-codepipeline"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "UseGitHubConnection"
        Effect   = "Allow"
        Action   = "codeconnections:UseConnection"
        Resource = aws_codestarconnections_connection.github.arn
      },
      {
        Sid    = "UseArtifactBucket"
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*"
        ]
      },
      {
        Sid    = "RunCodeBuild"
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds"
        ]
        Resource = values(aws_codebuild_project.pipeline_validation)[*].arn
      }
    ]
  })
}

resource "aws_codepipeline" "ci" {
  name          = var.project_name
  role_arn      = aws_iam_role.codepipeline.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "GitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.github.arn
        FullRepositoryId     = local.github_repository_id
        BranchName           = var.github_branch
        DetectChanges        = "true"
        OutputArtifactFormat = "CODEBUILD_CLONE_REF"
      }
    }
  }

  stage {
    name = "Validate"

    dynamic "action" {
      for_each = local.pipeline_validation_jobs
      content {
        name            = action.value.display_name
        category        = "Build"
        owner           = "AWS"
        provider        = "CodeBuild"
        version         = "1"
        run_order       = 1
        input_artifacts = ["SourceArtifact"]

        configuration = {
          ProjectName = aws_codebuild_project.pipeline_validation[action.key].name
        }
      }
    }
  }

  depends_on = [
    aws_iam_role_policy.codepipeline,
    aws_s3_bucket_lifecycle_configuration.pipeline_artifacts,
    aws_s3_bucket_policy.pipeline_artifacts,
    aws_s3_bucket_server_side_encryption_configuration.pipeline_artifacts
  ]
}
