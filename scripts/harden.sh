#!/usr/bin/env bash
set -euo pipefail

# --- SSM + CloudWatch agents are installed; enable them ---
sudo systemctl enable amazon-cloudwatch-agent || true

# --- basic hardening (CIS-style) ---
sudo sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
sudo sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y auditd
sudo systemctl enable auditd

# --- CLEANUP: critical for a golden image ---
sudo apt-get clean
sudo rm -rf /tmp/* /var/tmp/*
sudo rm -f /home/ubuntu/.ssh/authorized_keys   # temporary packer key
sudo truncate -s 0 /etc/machine-id             # avoid duplicate machine-id
cat /dev/null | sudo tee /var/log/cloud-init.log
history -c || true

echo "Hardening and cleanup complete."