# SPDX-License-Identifier: GPL-3.0-or-later

output "codebuild_project_name" {
  description = "Project name to pass to aws codebuild start-build."
  value       = aws_codebuild_project.ci.name
}

output "github_connection_arn" {
  description = "Authorize this pending connection once in the AWS console."
  value       = aws_codestarconnections_connection.github.arn
}

output "github_connection_status" {
  description = "PENDING until the GitHub App connection is authorized."
  value       = aws_codestarconnections_connection.github.connection_status
}

output "aws_account_id" {
  description = "Account receiving the learning resources."
  value       = data.aws_caller_identity.current.account_id
}
