# Step-by-Step Guide: Installing HashiCorp Vault on RHEL 9 VM

This guide walks you through manually installing HashiCorp Vault on a RHEL 9 virtual machine.

## Prerequisites

- RHEL 9 VM with root or sudo access
- Internet connectivity
- Minimum 2 CPU cores, 4GB RAM, 20GB disk space
- Static IP address configured (recommended)

---

## Step 1: Connect to Your RHEL 9 VM

```bash
# SSH into your RHEL 9 VM
ssh root@<your-vm-ip>
# OR if using a regular user with sudo:
ssh your-user@<your-vm-ip>
```

---

## Step 2: Update System Packages

```bash
# Update all system packages
sudo yum update -y

# Verify RHEL version
cat /etc/redhat-release
# Expected output: Red Hat Enterprise Linux release 9.x
```

---

## Step 3: Install Required Dependencies

```bash
# Install necessary packages
sudo yum install -y wget unzip curl jq firewalld

# Verify installations
wget --version
unzip -v
curl --version
jq --version
```

---

## Step 4: Download and Install Vault

```bash
# Set Vault version (check https://releases.hashicorp.com/vault/ for latest)
export VAULT_VERSION="1.21.4"

# Download Vault
cd /tmp
wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip

# Verify download
ls -lh vault_${VAULT_VERSION}_linux_amd64.zip

# Unzip Vault binary
unzip vault_${VAULT_VERSION}_linux_amd64.zip

# Move to system binary directory
sudo mv vault /usr/local/bin/

# Make it executable
sudo chmod +x /usr/local/bin/vault

# Verify installation
vault version
# Expected output: Vault v1.21.4 (...)

# Clean up
rm vault_${VAULT_VERSION}_linux_amd64.zip
```

---

## Step 5: Create Vault User and Directories

```bash
# Create vault system group
sudo groupadd --system vault

# Create vault system user
sudo useradd --system --home /etc/vault.d --shell /bin/false -g vault vault

# Verify user creation
id vault
# Expected output: uid=... gid=... groups=...

# Create Vault directories
sudo mkdir -p /etc/vault.d
sudo mkdir -p /opt/vault/data
sudo mkdir -p /opt/vault/logs
sudo mkdir -p /opt/vault/tls

# Set ownership
sudo chown -R vault:vault /etc/vault.d
sudo chown -R vault:vault /opt/vault

# Set permissions
sudo chmod 750 /etc/vault.d
sudo chmod 750 /opt/vault/data

# Verify directory structure
ls -la /etc/vault.d
ls -la /opt/vault
```

---

## Step 6: Configure Vault

```bash
# Create Vault configuration file
sudo tee /etc/vault.d/vault.hcl > /dev/null <<EOF
# Vault Server Configuration

# Storage backend - file storage for single node
storage "file" {
  path = "/opt/vault/data"
}

# HTTP listener
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

# API address - replace with your VM's IP
api_addr = "http://<your VM's IP>:8200"

# Cluster address
cluster_addr = "http://<your VM's IP>:8201"

# Enable UI
ui = true

# Log level
log_level = "Info"
disable_mlock = true

# Telemetry
telemetry {
  disable_hostname = false
  prometheus_retention_time = "30s"
}

# Lease configuration
default_lease_ttl = "168h"
max_lease_ttl = "720h"
EOF

# Set proper ownership and permissions
sudo chown vault:vault /etc/vault.d/vault.hcl
sudo chmod 640 /etc/vault.d/vault.hcl

# Verify configuration file
sudo cat /etc/vault.d/vault.hcl
```

---

## Step 7: Set Memory Lock Capability

```bash
# Give Vault the ability to use mlock
sudo setcap cap_ipc_lock=+ep /usr/local/bin/vault

# Verify capability
getcap /usr/local/bin/vault
# Expected output: /usr/local/bin/vault = cap_ipc_lock+ep
```

---

## Step 8: Create Systemd Service

```bash
# Create Vault systemd service file
sudo tee /etc/systemd/system/vault.service > /dev/null <<'EOF'
[Unit]
Description=HashiCorp Vault - A tool for managing secrets
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=notify
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

# Verify service file
sudo cat /etc/systemd/system/vault.service
```

---

## Step 9: Configure Firewall

```bash
# Enable and start firewalld
sudo systemctl enable firewalld
sudo systemctl start firewalld

# Check firewall status
sudo firewall-cmd --state
# Expected output: running

# Open Vault API port (8200)
sudo firewall-cmd --permanent --add-port=8200/tcp

# Open Vault cluster port (8201)
sudo firewall-cmd --permanent --add-port=8201/tcp

# Reload firewall to apply changes
sudo firewall-cmd --reload

# Verify firewall rules
sudo firewall-cmd --list-all
# Should show ports 8200/tcp and 8201/tcp
```

---

## Step 10: Configure SELinux (Optional)

```bash
# Check SELinux status
getenforce
# Output: Enforcing, Permissive, or Disabled

# For easier setup, set to permissive (NOT recommended for production)
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# Verify change
getenforce
# Expected output: Permissive

# NOTE: For production, keep SELinux enforcing and create custom policies
```

---

## Step 11: Set Environment Variables

```bash
# Create environment file for all users
sudo tee /etc/profile.d/vault.sh > /dev/null <<'EOF'
export VAULT_ADDR='http://<your VM's IP>:8200'
export VAULT_SKIP_VERIFY=true
EOF

# Make it executable
sudo chmod 644 /etc/profile.d/vault.sh

# Add to current user's bashrc
echo "export VAULT_ADDR='http://<your VM's IP>:8200'" >> ~/.bashrc

# Load environment variables
source /etc/profile.d/vault.sh
source ~/.bashrc

# Verify
echo $VAULT_ADDR
# Expected output: http://<your VM's IP>:8200
```

---

## Step 12: Start Vault Service

```bash
# Reload systemd to recognize new service
sudo systemctl daemon-reload

# Enable Vault to start on boot
sudo systemctl enable vault

# Reset the failed state
# sudo systemctl reset-failed vault

# Start Vault service
sudo systemctl start vault

# Check service status
sudo systemctl status vault
```
## Verify It's Working

```bash
# Should show "active (running)"
sudo systemctl status vault

# Check if listening on port 8200
sudo netstat -tlnp | grep 8200

# Test Vault status (will show as sealed, which is normal)
export VAULT_ADDR='http://<Your VM IP>:8200'
vault status
```

Expected output:
```
Key                Value
---                -----
Seal Type          shamir
Initialized        false
Sealed             true
...



# If there are issues, check logs
sudo journalctl -u vault -n 50 -f

```

---

## Step 13: Verify Vault is Running

```bash
# Check if Vault is listening on port 8200
sudo netstat -tlnp | grep 8200
# OR
sudo ss -tlnp | grep 8200
# Expected output: tcp ... 0.0.0.0:8200 ... LISTEN ... vault

# Check Vault status (will show as sealed)
vault status
# Expected output showing Sealed: true

# Test API endpoint (IMPORTANT: Use port 8200, not port 80!)
curl http://<your VM IP>:8200/v1/sys/health
# Should return JSON response
```

---

## Step 14: Initialize Vault

```bash
# Initialize Vault (ONLY RUN ONCE!)
vault operator init

# CRITICAL: Save the output! You'll see:
# - 5 Unseal Keys
# - 1 Initial Root Token
# 
# Example output:
# Unseal Key 1: AbCdEf1234567890...
# Unseal Key 2: GhIjKl1234567890...
# Unseal Key 3: MnOpQr1234567890...
# Unseal Key 4: StUvWx1234567890...
# Unseal Key 5: YzAbCd1234567890...
#
# Initial Root Token: hvs.1234567890abcdef...

# SAVE THESE KEYS SECURELY! Store them in:
# - Password manager
# - Encrypted file
# - Hardware security module
# - Split among team members

# You can also save to a file (SECURE THIS FILE!)
vault operator init > ~/vault-keys.txt
chmod 600 ~/vault-keys.txt
```

---

## Step 15: Unseal Vault

```bash
# Vault starts in a sealed state
# You need to unseal it with 3 of the 5 unseal keys

# Unseal with first key
vault operator unseal
# Paste Unseal Key 1 when prompted

# Unseal with second key
vault operator unseal
# Paste Unseal Key 2 when prompted

# Unseal with third key
vault operator unseal
# Paste Unseal Key 3 when prompted

# After the third key, Vault should be unsealed
# Verify status
vault status
# Expected output: Sealed: false
```

---

## Step 16: Login to Vault

```bash
# Login with the root token
vault login
# Paste the Initial Root Token when prompted

# OR login directly
vault login hvs.your-root-token-here

# Verify you're logged in
vault token lookup
# Should show information about your token
```

---

## Step 17: Verify Installation

```bash
# Check Vault status
vault status
# Should show:
# - Sealed: false
# - Initialized: true
# - Version: 1.21.4

# List enabled secrets engines
vault secrets list

# List enabled auth methods
vault auth list

# Check system health
vault read sys/health

# Access Vault UI
# Open browser to: http://<your-vm-ip>:8200
# Login with root token
```

---

## Step 18: Enable Audit Logging (Recommended)

```bash
# Enable file audit logging
vault audit enable file file_path=/opt/vault/logs/audit.log

# Verify audit device
vault audit list

# Check audit log
sudo tail -f /opt/vault/logs/audit.log
```

---

## Step 19: Create Your First Secret

```bash
# Enable KV secrets engine (v2)
vault secrets enable -path=secret kv-v2

# Write a secret
vault kv put secret/my-first-secret username="admin" password="supersecret"

# Read the secret
vault kv get secret/my-first-secret

# List secrets
vault kv list secret/
```

---

## Step 20: Secure Your Installation

```bash
# 1. Revoke root token (after creating other admin users)
# vault token revoke <root-token>

# 2. Enable additional auth methods
vault auth enable userpass

# 3. Create admin user
vault write auth/userpass/users/admin \
    password=changeme \
    policies=admin

# 4. Create admin policy
vault policy write admin - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

# 5. Test new admin user
vault login -method=userpass username=admin password=changeme
```

---

## Common Commands Reference

```bash
# Service Management
sudo systemctl start vault      # Start Vault
sudo systemctl stop vault       # Stop Vault
sudo systemctl restart vault    # Restart Vault
sudo systemctl status vault     # Check status
sudo journalctl -u vault -f     # View logs

# Vault Operations
vault status                    # Check Vault status
vault operator init             # Initialize Vault (once)
vault operator unseal           # Unseal Vault
vault operator seal             # Seal Vault
vault login                     # Login to Vault

# Secrets Management
vault kv put secret/path key=value    # Write secret
vault kv get secret/path              # Read secret
vault kv delete secret/path           # Delete secret
vault kv list secret/                 # List secrets

# Policy Management
vault policy list               # List policies
vault policy read <name>        # Read policy
vault policy write <name> <file> # Write policy

# Token Management
vault token lookup              # Check current token
vault token renew               # Renew token
vault token revoke <token>      # Revoke token
```

---

## Troubleshooting

### Vault Won't Start

```bash
# Check configuration syntax
sudo -u vault vault server -config=/etc/vault.d/vault.hcl -test

# Check logs
sudo journalctl -u vault -n 100 --no-pager

# Check permissions
ls -la /etc/vault.d/
ls -la /opt/vault/
```

### Cannot Connect to Vault

```bash
# Check if service is running
sudo systemctl status vault

# Check if port is listening
sudo netstat -tlnp | grep 8200

# Check firewall
sudo firewall-cmd --list-all

# Test locally
curl http://127.0.0.1:8200/v1/sys/health
```

### Vault is Sealed After Reboot

```bash
# This is normal! Vault seals on restart for security
# You must unseal it again with 3 unseal keys
vault operator unseal
# Enter key 1
vault operator unseal
# Enter key 2
vault operator unseal
# Enter key 3

# Check status
vault status
```

---

## Next Steps

1. **Enable TLS** - Configure HTTPS for production
2. **Set up High Availability** - Deploy multiple Vault nodes
3. **Configure Auto-Unseal** - Use HSM or cloud KMS
4. **Implement Backup Strategy** - Regular backups of Vault data
5. **Create Policies** - Implement least-privilege access
6. **Enable Auth Methods** - LDAP, OIDC, Kubernetes, etc.
7. **Monitor Vault** - Set up metrics and alerting

---

## Important Security Notes

⚠️ **CRITICAL REMINDERS:**

1. **NEVER lose your unseal keys** - Without them, you cannot access Vault
2. **NEVER commit secrets to version control**
3. **ALWAYS use TLS in production**
4. **ALWAYS restrict network access** with firewall rules
5. **ALWAYS enable audit logging**
6. **ALWAYS backup your Vault data** regularly
7. **ALWAYS rotate the root token** after initial setup
8. **ALWAYS use policies** for access control

---

## Resources

- [Vault Documentation](https://www.vaultproject.io/docs)
- [Vault Tutorials](https://learn.hashicorp.com/vault)
- [Production Hardening](https://learn.hashicorp.com/tutorials/vault/production-hardening)
- [Vault API Reference](https://www.vaultproject.io/api-docs)

---

**Installation Complete! 🎉**

Your Vault server is now running on RHEL 9. Remember to secure your unseal keys and root token!