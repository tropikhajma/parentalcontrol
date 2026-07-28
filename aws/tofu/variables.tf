# SPDX-License-Identifier: GPL-3.0-or-later

variable "aws_region" {
  description = "AWS Region for CodeBuild and CodeConnections."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Base name for Phase 1 AWS resources."
  type        = string
  default     = "familycontrol-ci"
}

variable "github_repository_url" {
  description = "HTTPS clone URL of the public GitHub repository."
  type        = string
  default     = "https://github.com/tropikhajma/parentalcontrol.git"
}

variable "github_branch" {
  description = "Branch built when no source version override is supplied."
  type        = string
  default     = "main"
}

variable "log_retention_days" {
  description = "CloudWatch build-log retention."
  type        = number
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90], var.log_retention_days)
    error_message = "Choose a supported short CloudWatch Logs retention period."
  }
}
