# Complete HashiCorp Vault Setup Guide with HTTPS
## From Installation to Production-Ready Configuration

This comprehensive guide covers installing HashiCorp Vault on RHEL 9 with HTTPS/TLS enabled, including all troubleshooting steps.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation Steps](#installation-steps)
3. [Enable HTTPS/TLS](#enable-httpstls)
4. [Common Issues and Fixes](#common-issues-and-fixes)
5. [Verification](#verification)
6. [Post-Installation](#post-installation)
7. [Quick Reference](#quick-reference)

---

## Prerequisites

- RHEL 9 VM with root or sudo access
- Internet connectivity
- Minimum 2 CPU cores, 4GB RAM, 20GB disk space
- Static IP address (e.g., <your VM's IP>)

---

## Installation Steps

### Step 1: Update System and Install Dependencies

```bash
# SSH into your RHEL 9 VM
ssh root@<your VM's IP>

# Update system packages
sudo yum update -y

# Install required packages
sudo yum install -y wget unzip curl jq firewalld openssl

# Verify installations
wget --version
unzip -v
curl --version
openssl version
```

### Step 2: Download and Install Vault

```bash
# Set Vault version (latest as of March 2026)
export VAULT_VERSION="1.21.4"

# Download Vault
cd /tmp
wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip

# Unzip and install
unzip vault_${VAULT_VERSION}_linux_amd64.zip
sudo mv vault /usr/local/bin/
sudo chmod +x /usr/local/bin/vault

# Verify installation
vault version
# Expected: Vault v1.21.4

# Clean up
rm vault_${VAULT_VERSION}_linux_amd64.zip
```

### Step 3: Create Vault User and Directories

```bash
# Create vault system group and user
sudo groupadd --system vault
sudo useradd --system --home /etc/vault.d --shell /bin/false -g vault vault

# Verify user creation
id vault

# Create required directories
sudo mkdir -p /etc/vault.d
sudo mkdir -p /opt/vault/data
sudo mkdir -p /opt/vault/logs
sudo mkdir -p /opt/vault/tls

# Set ownership and permissions
sudo chown -R vault:vault /etc/vault.d
sudo chown -R vault:vault /opt/vault
sudo chmod 750 /etc/vault.d
sudo chmod 750 /opt/vault/data

# Verify
ls -la /etc/vault.d
ls -la /opt/vault
```

### Step 4: Set Memory Lock Capability

```bash
# Give Vault the ability to use mlock
sudo setcap cap_ipc_lock=+ep /usr/local/bin/vault

# Verify capability
getcap /usr/local/bin/vault
# Expected: /usr/local/bin/vault = cap_ipc_lock+ep
```

### Step 5: Configure Firewall

```bash
# Enable and start firewalld
sudo systemctl enable firewalld
sudo systemctl start firewalld

# Open Vault ports
sudo firewall-cmd --permanent --add-port=8200/tcp
sudo firewall-cmd --permanent --add-port=8201/tcp

# Reload firewall
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-all
```

### Step 6: Configure SELinux (Optional for Development)

```bash
# Check SELinux status
getenforce

# For easier setup, set to permissive (NOT for production)
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# Verify
getenforce
```

---

## Enable HTTPS/TLS

### Step 7: Generate SSL Certificates

```bash
# Navigate to TLS directory
cd /opt/vault/tls

# Generate private key (2048-bit RSA)
sudo openssl genrsa -out vault-key.pem 2048

# Generate certificate signing request (CSR)
sudo openssl req -new -key vault-key.pem -out vault.csr \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=<your VM's IP>"

# Generate self-signed certificate (valid for 365 days)
sudo openssl x509 -req -days 365 -in vault.csr \
  -signkey vault-key.pem -out vault-cert.pem

# Set proper permissions
sudo chown -R vault:vault /opt/vault/tls
sudo chmod 600 /opt/vault/tls/vault-key.pem
sudo chmod 644 /opt/vault/tls/vault-cert.pem

# Verify files
ls -la /opt/vault/tls/
```

### Step 8: Create Vault Configuration with HTTPS

```bash
# Create Vault configuration file with TLS enabled
sudo tee /etc/vault.d/vault.hcl > /dev/null <<'EOF'
# Vault Server Configuration with TLS/HTTPS

# Storage backend
storage "file" {
  path = "/opt/vault/data"
}

# HTTPS listener with TLS enabled
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = 0
  tls_cert_file = "/opt/vault/tls/vault-cert.pem"
  tls_key_file  = "/opt/vault/tls/vault-key.pem"
}

# API address - IMPORTANT: Use https://
api_addr = "https://<your VM's IP>:8200"

# Cluster address
cluster_addr = "https://<your VM's IP>:8201"

# Enable UI
ui = true

# Log level
log_level = "Info"

# Disable mlock for easier setup
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

# Verify configuration syntax
sudo -u vault /usr/local/bin/vault server -config=/etc/vault.d/vault.hcl 
# Should output: "Configuration is valid!"
```

### Step 9: Create Systemd Service

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

### Step 10: Start Vault Service

```bash
# Reload systemd to recognize new service
sudo systemctl daemon-reload

# Enable Vault to start on boot
sudo systemctl enable vault

# Start Vault service
sudo systemctl start vault

# Check service status
sudo systemctl status vault
# Should show: "active (running)"

# Check if listening on port 8200
sudo netstat -tlnp | grep 8200
# OR
sudo ss -tlnp | grep 8200
```

### Step 11: Configure Environment Variables

```bash
# Set environment variables for HTTPS
export VAULT_ADDR='https://<your VM's IP>:8200'
export VAULT_SKIP_VERIFY=true  # For self-signed certificates

# Verify
echo $VAULT_ADDR
echo $VAULT_SKIP_VERIFY

# Make permanent for current user
cat >> ~/.bashrc <<'EOF'
export VAULT_ADDR='https://<your VM's IP>:8200'
export VAULT_SKIP_VERIFY=true
EOF

# Reload bashrc
source ~/.bashrc

# Create system-wide environment file
sudo tee /etc/profile.d/vault.sh > /dev/null <<'EOF'
export VAULT_ADDR='https://<your VM's IP>:8200'
export VAULT_SKIP_VERIFY=true
EOF

sudo chmod 644 /etc/profile.d/vault.sh
source /etc/profile.d/vault.sh
```

### Step 12: Test HTTPS Connection

```bash
# Test with Vault CLI
vault status
# Should show Vault status (sealed is normal)

# Test with curl
curl -k https://<your VM's IP>:8200/v1/sys/health
# Should return JSON response
```

---

## Common Issues and Fixes

### Issue 1: Configuration Syntax Error

**Error:**
```
error loading configuration from /etc/vault.d/vault.hcl: At 38:2: object expected closing RBRACE got: EOF
```

**Fix:**
```bash
# The configuration file has a syntax error (missing closing brace)
# Replace with corrected configuration (see Step 8 above)

# Test configuration syntax
sudo -u vault /usr/local/bin/vault server -config=/etc/vault.d/vault.hcl -test
```

### Issue 2: HTTP Request to HTTPS Server

**Error:**
```
Client sent an HTTP request to an HTTPS server.
```

**Fix:**
```bash
# Your VAULT_ADDR is set to HTTP but Vault is running HTTPS
# Update environment variable
export VAULT_ADDR='https://<your VM's IP>:8200'
export VAULT_SKIP_VERIFY=true

# Make permanent
echo 'export VAULT_ADDR="https://<your VM's IP>:8200"' >> ~/.bashrc
echo 'export VAULT_SKIP_VERIFY=true' >> ~/.bashrc
source ~/.bashrc
```

### Issue 3: HTTPS Request to HTTP Server

**Error:**
```
http: server gave HTTP response to HTTPS client
```

**Fix:**
```bash
# Your VAULT_ADDR is set to HTTPS but Vault is running HTTP
# Update environment variable
export VAULT_ADDR='http://<your VM's IP>:8200'

# OR enable TLS in Vault configuration (see Step 8)
```

### Issue 4: Certificate Files Missing

**Error:**
```
no such file or directory: /opt/vault/tls/vault-cert.pem
```

**Fix:**
```bash
# Generate certificates (see Step 7)
cd /opt/vault/tls
sudo openssl genrsa -out vault-key.pem 2048
sudo openssl req -new -key vault-key.pem -out vault.csr -subj "/C=US/ST=State/L=City/O=Organization/CN=<your VM's IP>"
sudo openssl x509 -req -days 365 -in vault.csr -signkey vault-key.pem -out vault-cert.pem
sudo chown -R vault:vault /opt/vault/tls
sudo chmod 600 /opt/vault/tls/vault-key.pem
sudo chmod 644 /opt/vault/tls/vault-cert.pem
```

### Issue 5: Permission Denied

**Error:**
```
permission denied
```

**Fix:**
```bash
# Fix file permissions
sudo chown -R vault:vault /opt/vault
sudo chown -R vault:vault /etc/vault.d
sudo chmod 750 /opt/vault/data
sudo chmod 640 /etc/vault.d/vault.hcl
sudo chmod 600 /opt/vault/tls/vault-key.pem
sudo chmod 644 /opt/vault/tls/vault-cert.pem
```

### Issue 6: Port Already in Use

**Error:**
```
address already in use
```

**Fix:**
```bash
# Check what's using port 8200
sudo netstat -tlnp | grep 8200

# Kill the process
sudo kill -9 <PID>

# Restart Vault
sudo systemctl restart vault
```

### Issue 7: Vault Won't Start

**Fix:**
```bash
# Check logs for specific error
sudo journalctl -u vault.service -n 50 --no-pager

# Test configuration
sudo -u vault /usr/local/bin/vault server -config=/etc/vault.d/vault.hcl -test

# Check file permissions
ls -la /etc/vault.d/
ls -la /opt/vault/tls/

# Reset and restart
sudo systemctl reset-failed vault
sudo systemctl daemon-reload
sudo systemctl restart vault
sudo systemctl status vault
```

---

## Verification

### Step 13: Verify Vault is Running

```bash
# 1. Check service status
sudo systemctl status vault
# Should show: active (running)

# 2. Check logs (no errors)
sudo journalctl -u vault -n 20 --no-pager

# 3. Check port is listening
sudo netstat -tlnp | grep 8200

# 4. Test connection
vault status
# Should show Vault status (sealed is normal)

# 5. Test with curl
curl -k https://<your VM's IP>:8200/v1/sys/health
# Should return JSON

# 6. Verify environment variables
echo $VAULT_ADDR
# Should output: https://<your VM's IP>:8200
```

---

## Post-Installation

### Step 14: Initialize Vault

```bash
# Initialize Vault (ONLY RUN ONCE!)
vault operator init

# CRITICAL: Save the output!
# You'll receive:
# - 5 Unseal Keys
# - 1 Initial Root Token

# Save to a secure file
vault operator init > ~/vault-keys.txt
chmod 600 ~/vault-keys.txt

# IMPORTANT: Store these keys securely!
# - Password manager
# - Encrypted file
# - Hardware security module
# - Split among team members
```

### Step 15: Unseal Vault

```bash
# Vault starts in a sealed state
# You need 3 of the 5 unseal keys

# Unseal with first key
vault operator unseal
# Paste Unseal Key 1

# Unseal with second key
vault operator unseal
# Paste Unseal Key 2

# Unseal with third key
vault operator unseal
# Paste Unseal Key 3

# Verify status
vault status
# Should show: Sealed: false
```

### Step 16: Login to Vault

```bash
# Login with root token
vault login
# Paste the Initial Root Token

# Verify you're logged in
vault token lookup

# Access Vault UI
# Open browser to: https://<your VM's IP>:8200
# Login with root token
```

### Step 17: Enable Audit Logging

```bash
# Enable file audit logging
vault audit enable file file_path=/opt/vault/logs/audit.log

# Verify audit device
vault audit list

# Check audit log
sudo tail -f /opt/vault/logs/audit.log
```

### Step 18: Create Your First Secret

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

### Step 19: Secure Your Installation

```bash
# 1. Enable additional auth methods
vault auth enable userpass

# 2. Create admin policy
vault policy write admin - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

# 3. Create admin user
vault write auth/userpass/users/admin \
    password=changeme \
    policies=admin

# 4. Test new admin user
vault login -method=userpass username=admin password=changeme

# 5. Revoke root token (after creating other admin users)
# vault token revoke <root-token>
```

---

## Quick Reference

### Common Commands

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

### Configuration Reference

| Setting | HTTP | HTTPS |
|---------|------|-------|
| tls_disable | 1 | 0 |
| VAULT_ADDR | http://<your VM's IP>:8200 | https://<your VM's IP>:8200 |
| api_addr | http://<your VM's IP>:8200 | https://<your VM's IP>:8200 |
| Port | 8200 | 8200 |
| Certificate Required | No | Yes |

### Troubleshooting Commands

```bash
# Check service status
sudo systemctl status vault

# View logs
sudo journalctl -u vault.service -n 50 --no-pager

# Test configuration
sudo -u vault vault server -config=/etc/vault.d/vault.hcl -test

# Check certificates
ls -la /opt/vault/tls/
openssl x509 -in /opt/vault/tls/vault-cert.pem -text -noout | head -20

# Check port
sudo netstat -tlnp | grep 8200

# Check environment
echo $VAULT_ADDR
echo $VAULT_SKIP_VERIFY

# Test connection
vault status
curl -k https://<your VM's IP>:8200/v1/sys/health
```

---

## Production Considerations

### 1. Use CA-Signed Certificates

Replace self-signed certificates with certificates from a trusted CA:

```bash
# Option 1: Let's Encrypt (Free)
sudo yum install -y certbot
sudo certbot certonly --standalone -d your-domain.com

# Option 2: Your Organization's CA
# Get certificates from your CA and place in /opt/vault/tls/
```

### 2. Remove VAULT_SKIP_VERIFY

```bash
# For production, don't skip certificate verification
# Remove from ~/.bashrc and /etc/profile.d/vault.sh
unset VAULT_SKIP_VERIFY

# Instead, specify CA certificate
export VAULT_CACERT=/opt/vault/tls/ca-bundle.crt
```

### 3. Enable High Availability

Deploy multiple Vault nodes with a shared storage backend (Consul, etcd, etc.)

### 4. Configure Auto-Unseal

Use HSM or cloud KMS for automatic unsealing

### 5. Implement Backup Strategy

Regular backups of:
- Vault data directory (`/opt/vault/data`)
- Configuration files
- Unseal keys (stored securely)

### 6. Enable Monitoring

Set up metrics and alerting:
- Prometheus for metrics
- Grafana for dashboards
- Alert on seal status, performance, errors

### 7. Rotate Root Token

```bash
# Generate new root token
vault operator generate-root

# Revoke old root token
vault token revoke <old-root-token>
```

---

## Important Security Notes

⚠️ **CRITICAL REMINDERS:**

1. **NEVER lose your unseal keys** - Without them, you cannot access Vault
2. **NEVER commit secrets to version control**
3. **ALWAYS use TLS in production** - Never use HTTP in production
4. **ALWAYS restrict network access** with firewall rules
5. **ALWAYS enable audit logging**
6. **ALWAYS backup your Vault data** regularly
7. **ALWAYS rotate the root token** after initial setup
8. **ALWAYS use policies** for access control
9. **NEVER use VAULT_SKIP_VERIFY in production**
10. **ALWAYS use CA-signed certificates in production**

---

## Resources

- [Vault Documentation](https://www.vaultproject.io/docs)
- [Vault Tutorials](https://learn.hashicorp.com/vault)
- [Production Hardening](https://learn.hashicorp.com/tutorials/vault/production-hardening)
- [Vault API Reference](https://www.vaultproject.io/api-docs)
- [Vault GitHub](https://github.com/hashicorp/vault)

---

## Summary

You now have a fully functional HashiCorp Vault installation with HTTPS/TLS enabled:

✅ Vault v1.21.4 installed  
✅ HTTPS/TLS configured with self-signed certificates  
✅ Systemd service configured and running  
✅ Firewall rules configured  
✅ Environment variables set  
✅ Ready for initialization and use  

**Next Steps:**
1. Initialize Vault
2. Unseal Vault
3. Login and start managing secrets
4. For production: Replace self-signed certificates with CA-signed certificates

---

**Installation Complete! 🎉🔒**

Your Vault server is now running securely with HTTPS on RHEL 9!
