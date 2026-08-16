# file: terraform/main.tf
# Consumes the latest golden AMI (built by Packer) into a Launch Template + ASG.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-central-1"
}

provider "aws" {
  region = var.region
}

# --- Fallback: if subnet_ids isn't supplied, use the default VPC's subnets ---
data "aws_vpc" "default" {
  count   = length(var.subnet_ids) == 0 ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}

locals {
  # Prefer explicitly passed subnet_ids; otherwise fall back to the default VPC's subnets.
  asg_subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
}

# --- Always pick up the newest AMI built and tagged by Packer ---
data "aws_ami" "golden" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "tag:ManagedBy"
    values = ["packer"]
  }

  filter {
    name   = "name"
    values = ["golden-ubuntu22-*"]
  }
}

# --- IAM role/instance profile so instances can register with SSM (Session Manager) ---
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_instance" {
  name               = "app-golden-ami-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app_instance" {
  name = "app-golden-ami-instance-profile"
  role = aws_iam_role.app_instance.name
}

resource "aws_launch_template" "app" {
  name_prefix   = "app-"
  image_id      = data.aws_ami.golden.id
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.app_instance.name
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "app-from-golden-ami"
    }
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "app-asg"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = local.asg_subnet_ids

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Rolling replacement whenever the launch template (i.e. the golden AMI) changes
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "app-asg-instance"
    propagate_at_launch = true
  }
}

variable "subnet_ids" {
  description = "Subnets for the Auto Scaling Group. Leave empty to auto-discover the default VPC's subnets (fine for a lab/demo; pass explicit subnet IDs for real environments)."
  type        = list(string)
  default     = []
}

output "golden_ami_id" {
  value = data.aws_ami.golden.id
}
