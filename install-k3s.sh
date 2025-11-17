#!/bin/bash

set -e

echo "=========================================="
echo "K3s Installation Script for Ubuntu LTS"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    echo "Please run with: sudo $0"
    exit 1
fi

echo "✓ Running as root"

# Increase open files limit for all users
echo ""
echo "Configuring system limits..."
echo "* soft nofile 131072" >> /etc/security/limits.conf
echo "* hard nofile 131072" >> /etc/security/limits.conf
echo "✓ Open files limit set to 131072 for all users"

# Configure logsettings to avoid running out of file handles
sudo mkdir -p /etc/rancher/k3s
# If /etc/rancher/k3s/config.yaml already exists, merge these lines into the existing 'kubelet-arg:' list.
cat <<'EOF' | sudo tee -a /etc/rancher/k3s/config.yaml
kubelet-arg:
  - container-log-max-size=10Mi
  - container-log-max-files=3
EOF
echo "✓ k3s logs configured"

# Disable UFW firewall (for demo environment)
echo ""
echo "Disabling UFW firewall..."
if systemctl is-active --quiet ufw; then
    ufw disable
    echo "✓ UFW firewall disabled"
else
    echo "✓ UFW is not active"
fi
echo ""
echo "Installing Flux cli..."
# Install Flux cli
curl -s https://fluxcd.io/install.sh | sudo bash

# Install k3s
echo ""
echo "Installing k3s (latest stable version)..."
curl -sfL https://get.k3s.io | sh -

# Wait for k3s to be ready
echo ""
echo "Waiting for k3s to be ready..."
sleep 10

# Check if k3s service is running
if systemctl is-active --quiet k3s; then
    echo "✓ k3s service is running"
else
    echo "Error: k3s service failed to start"
    systemctl status k3s
    exit 1
fi

# Set up kubeconfig for the current user
echo ""
echo "Setting up kubeconfig..."

# Get the original user who ran sudo (if sudo was used)
if [ -n "$SUDO_USER" ]; then
    ORIGINAL_USER=$SUDO_USER
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    ORIGINAL_USER=$(whoami)
    USER_HOME=$HOME
fi

# Create .kube directory for the user
mkdir -p "$USER_HOME/.kube"

# Copy k3s config to user's kubeconfig
cp /etc/rancher/k3s/k3s.yaml "$USER_HOME/.kube/config"

# Set proper ownership
chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$USER_HOME/.kube"
chmod 600 "$USER_HOME/.kube/config"
chmod 755 /etc/rancher/k3s/k3s.yaml

echo "✓ kubeconfig set up at $USER_HOME/.kube/config"

# Also set KUBECONFIG environment variable hint
echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "k3s is now running as a daemon (systemd service)"
echo ""
echo "You can now run kubectl commands directly:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo ""
echo "To check k3s service status:"
echo "  sudo systemctl status k3s"
echo ""
echo "To view k3s logs:"
echo "  sudo journalctl -u k3s -f"
echo ""