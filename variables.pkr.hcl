variable "region" {
  type        = string
  description = "AWS region to build the AMI in"
  default     = "eu-central-1"
}

variable "instance_type" {
  type        = string
  description = "Temporary EC2 instance type used during the build"
  default     = "t3.micro"
}

variable "app_version" {
  type        = string
  description = "Application version baked into this image (traceability tag)"
  default     = "0.0.0"
}

variable "environment" {
  type        = string
  description = "Target environment for this build: dev | staging | prod"
  default     = "dev"
}

variable "git_sha" {
  type        = string
  description = "Git commit SHA the build was triggered from (traceability tag)"
  default     = "unknown"
}
