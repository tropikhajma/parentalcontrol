# SPDX-License-Identifier: GPL-3.0-or-later

data "aws_caller_identity" "current" {}

resource "aws_codestarconnections_connection" "github" {
  name          = "${var.project_name}-github"
  provider_type = "GitHub"
}

resource "aws_codebuild_source_credential" "github" {
  auth_type   = "CODECONNECTIONS"
  server_type = "GITHUB"
  token       = aws_codestarconnections_connection.github.arn
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "codebuild" {
  name = "${var.project_name}-codebuild"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.project_name}-codebuild"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteBuildLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.codebuild.arn}:*"
      },
      {
        Sid    = "UseGitHubConnection"
        Effect = "Allow"
        Action = [
          "codeconnections:GetConnection",
          "codeconnections:GetConnectionToken",
          "codeconnections:UseConnection"
        ]
        Resource = aws_codestarconnections_connection.github.arn
      },
      {
        Sid    = "ReadPipelineSourceArtifact"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.pipeline_artifacts.arn}/*"
      }
    ]
  })
}

resource "aws_codebuild_project" "ci" {
  name          = var.project_name
  description   = "Manual Phase 1 CI for Family Control"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 15

  artifacts {
    type = "NO_ARTIFACTS"
  }

  cache {
    type = "LOCAL"
    modes = [
      "LOCAL_DOCKER_LAYER_CACHE",
      "LOCAL_SOURCE_CACHE"
    ]
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "build"
      status      = "ENABLED"
    }

    s3_logs {
      status = "DISABLED"
    }
  }

  source {
    type                = "GITHUB"
    location            = var.github_repository_url
    buildspec           = "aws/buildspec-ci.yml"
    git_clone_depth     = 1
    report_build_status = false

    auth {
      type     = "CODECONNECTIONS"
      resource = aws_codestarconnections_connection.github.arn
    }
  }

  source_version = "refs/heads/${var.github_branch}"

  depends_on = [
    aws_codebuild_source_credential.github,
    aws_iam_role_policy.codebuild
  ]
}
