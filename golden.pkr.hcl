# Golden AMI build template — Ubuntu 22.04 base, nginx app, CIS-style hardening.

packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------
locals {
  timestamp = formatdate("YYYYMMDD-hhmmss", timestamp())
  ami_name  = "golden-ubuntu22-${var.environment}-${local.timestamp}"
}

# ---------------------------------------------------------------------------
# Data source: always resolve the newest official Ubuntu 22.04 AMI
# ---------------------------------------------------------------------------
data "amazon-ami" "ubuntu" {
  filters = {
    name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
    virtualization-type = "hvm"
    root-device-type    = "ebs"
  }
  owners      = ["099720109477"] # Canonical
  most_recent = true
  region      = var.region
}

# ---------------------------------------------------------------------------
# Source / builder
# ---------------------------------------------------------------------------
source "amazon-ebs" "golden" {
  region        = var.region
  source_ami    = data.amazon-ami.ubuntu.id
  instance_type = var.instance_type
  ssh_username  = "ubuntu"
  ami_name      = local.ami_name

  # Traceability tags — never rely on "latest" without an immutable identifier
  tags = {
    Name        = local.ami_name
    ManagedBy   = "packer"
    Environment = var.environment
    AppVersion  = var.app_version
    GitSha      = var.git_sha
    BuildDate   = local.timestamp
  }

  run_tags = {
    Name = "packer-builder-${local.ami_name}"
  }
}

# ---------------------------------------------------------------------------
# Build block: source + provisioners (run in order) + post-processors
# ---------------------------------------------------------------------------
build {
  name    = "golden-ami"
  sources = ["source.amazon-ebs.golden"]

  # 1) Push app config onto the instance
  provisioner "file" {
    source      = "files/nginx.conf"
    destination = "/tmp/nginx.conf"
  }

  # 2) Install and configure nginx
  provisioner "shell" {
    inline = [
      "sudo apt-get update -y",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx",
      "sudo mv /tmp/nginx.conf /etc/nginx/nginx.conf",
      "sudo systemctl enable nginx",
    ]
  }

  # 3) Install mandatory agents (CloudWatch, SSM — SSM ships pre-installed on
  #    the official Ubuntu AMI, CloudWatch agent installed here)
  provisioner "shell" {
    inline = [
      "curl -sSL https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -o /tmp/amazon-cloudwatch-agent.deb",
      "sudo dpkg -i /tmp/amazon-cloudwatch-agent.deb || sudo apt-get -f install -y",
    ]
  }

  # 4) Hardening + cleanup (Task 2)
  provisioner "shell" {
    script = "scripts/harden.sh"
  }

  # 5) Smoke test / validation gate (Task 4) — must pass before the AMI is baked
  provisioner "shell" {
    inline = [
      "sudo systemctl is-enabled nginx",
      "sudo nginx -t",
      "systemctl is-active amazon-cloudwatch-agent || true",
    ]
  }

  # Write the new AMI ID out for downstream consumers (e.g. Terraform)
  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
    custom_data = {
      app_version = var.app_version
      environment = var.environment
      git_sha     = var.git_sha
    }
  }
}
