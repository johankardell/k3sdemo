# k3sdemo

A demo environment for running k3s on Ubuntu LTS.

## Quick Start

This repository contains a shell script to quickly install and configure k3s on the latest Ubuntu LTS version.

### Prerequisites

- Ubuntu LTS (20.04, 22.04, or later)
- Root access (via sudo)
- Internet connection

### Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/johankardell/k3sdemo.git
   cd k3sdemo
   ```

2. Run the installation script:
   ```bash
   sudo ./install-k3s.sh
   ```

The script will:
- Check for root access
- Disable UFW firewall (for demo simplicity)
- Install the latest stable version of k3s
- Configure k3s to run as a systemd daemon
- Set up kubeconfig for kubectl access

### Usage

After installation, you can immediately start using kubectl:

```bash
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

### Managing k3s Service

Check k3s service status:
```bash
sudo systemctl status k3s
```

View k3s logs:
```bash
sudo journalctl -u k3s -f
```

Restart k3s:
```bash
sudo systemctl restart k3s
```

### Uninstalling

To uninstall k3s:
```bash
sudo /usr/local/bin/k3s-uninstall.sh
```

## Notes

- This is a demo environment intended for short-term use (a few hours)
- Security features like UFW are disabled for simplicity
- The script assumes local access to the VM with root privileges
- k3s runs as a systemd service and will automatically start on boot