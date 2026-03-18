# HashiCorp Vault Enterprise Setup Guide

This guide covers installing and configuring Vault Enterprise on RHEL 9 with advanced enterprise features.

---

## Table of Contents

1. [Vault Enterprise vs Open Source](#vault-enterprise-vs-open-source)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Enterprise License](#enterprise-license)
5. [Enterprise Features Configuration](#enterprise-features-configuration)
6. [High Availability Setup](#high-availability-setup)
7. [Disaster Recovery](#disaster-recovery)
8. [Performance Replication](#performance-replication)
9. [HSM Auto-Unseal](#hsm-auto-unseal)
10. [Namespaces](#namespaces)
11. [Sentinel Policies](#sentinel-policies)
12. [Monitoring and Telemetry](#monitoring-and-telemetry)

---

## Vault Enterprise vs Open Source

### Enterprise Features

| Feature | Open Source | Enterprise |
|---------|-------------|------------|
| Basic Secrets Management | ✅ | ✅ |
| Authentication Methods | ✅ | ✅ |
| Audit Logging | ✅ | ✅ |
| High Availability | ✅ | ✅ |
| **Disaster Recovery Replication** | ❌ | ✅ |
| **Performance Replication** | ❌ | ✅ |
| **HSM Auto-Unseal** | ❌ | ✅ |
| **Namespaces** | ❌ | ✅ |
| **Sentinel Policies** | ❌ | ✅ |
| **Control Groups** | ❌ | ✅ |
| **MFA** | ❌ | ✅ |
| **FIPS 140-2 Compliance** | ❌ | ✅ |
| **Read Replicas** | ❌ | ✅ |
| **Seal Wrap** | ❌ | ✅ |
| **Key Management Secrets Engine** | ❌ | ✅ |
| **Transform Secrets Engine** | ❌ | ✅ |
| **Advanced Data Protection** | ❌ | ✅ |

---

## Prerequisites

- RHEL 9 VM with root or sudo access
- Valid Vault Enterprise license
- Minimum 4 CPU cores, 8GB RAM, 50GB disk space
- Static IP addresses for all nodes
- Network connectivity between nodes
- (Optional) HSM device for auto-unseal
## Install Required Dependencies

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
---

## Installation

### Step 1: Download Vault Enterprise

```bash
# Set Vault Enterprise version
export VAULT_VERSION="1.21.4+ent"

# Download Vault Enterprise (requires license)
cd /tmp
wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip

# Or if you have a custom download URL from HashiCorp
# wget <your-custom-enterprise-download-url>

# Unzip and install
unzip vault_${VAULT_VERSION}_linux_amd64.zip
sudo mv vault /usr/local/bin/
sudo chmod +x /usr/local/bin/vault

# Verify installation
vault version
# Expected: Vault v1.21.4+ent (enterprise)

# Clean up
rm vault_${VAULT_VERSION}_linux_amd64.zip
```

### Step 2: Create Vault User and Directories

```bash
# Create vault system group and user
sudo groupadd --system vault
sudo useradd --system --home /etc/vault.d --shell /bin/false -g vault vault

# Create required directories
sudo mkdir -p /etc/vault.d
sudo mkdir -p /opt/vault/data
sudo mkdir -p /opt/vault/logs
sudo mkdir -p /opt/vault/tls
sudo mkdir -p /opt/vault/plugins

# Set ownership and permissions
sudo chown -R vault:vault /etc/vault.d
sudo chown -R vault:vault /opt/vault
sudo chmod 750 /etc/vault.d
sudo chmod 750 /opt/vault/data
```

### Step 3: Generate SSL Certificates

```bash
# Generate certificates for HTTPS
cd /opt/vault/tls

sudo openssl genrsa -out vault-key.pem 2048
sudo openssl req -new -key vault-key.pem -out vault.csr \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=< IP-Address>"
sudo openssl x509 -req -days 365 -in vault.csr \
  -signkey vault-key.pem -out vault-cert.pem

sudo chown -R vault:vault /opt/vault/tls
sudo chmod 600 /opt/vault/tls/vault-key.pem
sudo chmod 644 /opt/vault/tls/vault-cert.pem
```

### Step 4: Configure Vault Enterprise

- Create license file

```bash

sudo tee /etc/vault.d/vault.hclic > /dev/null <<'EOF'
<YOUR-ENTERPRISE-LICENSE-STRING>
EOF

# **Set proper ownership and permissions **
sudo chown vault:vault /etc/vault.d/vault.hclic
sudo chmod 640 /etc/vault.d/vault.hclic
```

```bash
# Create Vault Enterprise configuration
sudo tee /etc/vault.d/vault.hcl > /dev/null <<'EOF'
# Vault Enterprise Configuration

# Storage backend - use Consul or Raft for HA
storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-node-1"
  
  # For HA cluster, add retry_join blocks
  # retry_join {
  #   leader_api_addr = "https://vault-node-2:8200"
  # }
  # retry_join {
  #   leader_api_addr = "https://vault-node-3:8200"
  # }
}

# HTTPS listener
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = 0
  tls_cert_file = "/opt/vault/tls/vault-cert.pem"
  tls_key_file  = "/opt/vault/tls/vault-key.pem"
  
  # Enable telemetry
  telemetry {
    unauthenticated_metrics_access = true
  }
}

# API and cluster addresses
api_addr     = "https://< IP-Address>:8200"
cluster_addr = "https://< IP-Address>:8201"

# Enable UI
ui = true

# Log level
log_level = "Info"

# Disable mlock (or enable with proper capabilities)
disable_mlock = true

# Enterprise license path (will be set via API)
license_path = "/etc/vault.d/vault.hclic"

# Telemetry for monitoring
telemetry {
  disable_hostname          = false
  prometheus_retention_time = "30s"
  
  # Uncomment for Prometheus integration
  # prometheus_retention_time = "24h"
}

# Seal configuration (for HSM auto-unseal)
# seal "pkcs11" {
#   lib            = "/usr/lib/libCryptoki2_64.so"
#   slot           = "0"
#   pin            = "AAAA-BBBB-CCCC-DDDD"
#   key_label      = "vault-hsm-key"
#   hmac_key_label = "vault-hsm-hmac-key"
# }

# Default and max lease TTL
default_lease_ttl = "168h"
max_lease_ttl     = "720h"

# Plugin directory
plugin_directory = "/opt/vault/plugins"

# Enable raw endpoint (for debugging)
raw_storage_endpoint = true

# Cluster name
cluster_name = "vault-enterprise-cluster"
EOF

# Set permissions
sudo chown vault:vault /etc/vault.d/vault.hcl
sudo chmod 640 /etc/vault.d/vault.hcl
```

### Step 5: Create Systemd Service

```bash
# Create systemd service file
sudo tee /etc/systemd/system/vault.service > /dev/null <<'EOF'
[Unit]
Description=HashiCorp Vault Enterprise
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

```

---

## Enterprise License ( Optional )

### Step 6: Apply Enterprise License

```bash
# Create environment file for all users
sudo tee /etc/profile.d/vault.sh > /dev/null <<'EOF'
export VAULT_ADDR='https://<your VM's IP>:8200'
export VAULT_SKIP_VERIFY=true
EOF

# Make it executable
sudo chmod 644 /etc/profile.d/vault.sh

# Add to current user's bashrc
echo "export VAULT_ADDR='http://<your VM's IP>:8200'" > > ~/.bashrc

# Load environment variables
source /etc/profile.d/vault.sh
source ~/.bashrc

# Verify
echo $VAULT_ADDR
# Expected output: http://<your VM's IP>:8200
```

---

### Alternative: License File

```bash
# Save license to file
sudo tee /etc/vault.d/vault.hclic > /dev/null <<'EOF'
<YOUR-ENTERPRISE-LICENSE-STRING>
EOF

sudo chown vault:vault /etc/vault.d/vault.hclic
sudo chmod 640 /etc/vault.d/vault.hclic

# Update vault.hcl to include license_path
# sudo sed -i '/# license_path/c\license_path = "/etc/vault.d/vault.hclic"' /etc/vault.d/vault.hcl

# Restart Vault
# sudo systemctl restart vault
```

---
# Step 7 Start Vault Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault
sudo systemctl status vault
# Should show "active (running)"
```
## Verify It's Working

```bash
# Check if listening on port 8200
sudo netstat -tlnp | grep 8200

# Test Vault status (will show as sealed, which is normal)
export VAULT_ADDR='http://<Your VM IP>:8200'
vault status
```

## Enterprise Features Configuration
## Step 9: Configure Firewall ( Optional )

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
## Step 10: Initialize Vault

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

## Step 11: Unseal Vault

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
## Step 12: Login to Vault

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

## Step 13: Verify Installation

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
# Open browser to: https://<your-vm-ip>:8200
# Login with root token
```

---

## Step 14: Enable Audit Logging (Recommended)

```bash
# Enable file audit logging
vault audit enable file file_path=/opt/vault/logs/audit.log

# Verify audit device
vault audit list

# Check audit log
sudo tail -f /opt/vault/logs/audit.log
```

---

## Step 15: Create Your First Secret

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

## Step 16: Secure Your Installation

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


### Namespaces

```bash
# Create namespace
vault namespace create engineering
vault namespace create finance
vault namespace create operations

# List namespaces
vault namespace list

# Create nested namespace
vault namespace create -namespace=engineering dev
vault namespace create -namespace=engineering prod

# Set namespace in environment
export VAULT_NAMESPACE=engineering

# Create secrets in namespace
vault secrets enable -path=secret kv-v2
vault kv put secret/app-config api_key="secret123"

# Access from different namespace
vault kv get -namespace=engineering secret/app-config
```

### Performance Replication

```bash
# On Primary Cluster
# Enable replication
vault write -f sys/replication/performance/primary/enable

# Generate secondary token
vault write sys/replication/performance/primary/secondary-token id=secondary-1

# On Secondary Cluster
# Enable as secondary
vault write sys/replication/performance/secondary/enable token=<token-from-primary>

# Check replication status
vault read sys/replication/performance/status
```

### Disaster Recovery Replication

```bash
# On Primary Cluster
# Enable DR replication
vault write -f sys/replication/dr/primary/enable

# Generate DR secondary token
vault write sys/replication/dr/primary/secondary-token id=dr-secondary-1

# On DR Secondary Cluster
# Enable as DR secondary
vault write sys/replication/dr/secondary/enable token=<token-from-primary>

# Check DR status
vault read sys/replication/dr/status

# Promote DR secondary to primary (in disaster scenario)
vault write -f sys/replication/dr/secondary/promote
```

### Sentinel Policies

```bash
# Create Sentinel policy
vault write sys/policies/egp/business-hours-only \
  policy=@business-hours.sentinel \
  enforcement_level="hard-mandatory" \
  paths="secret/*"

# Example Sentinel policy (business-hours.sentinel)
cat > business-hours.sentinel <<'EOF'
import "time"

# Get current hour
current_hour = time.now.hour

# Business hours: 9 AM to 5 PM
main = rule {
  current_hour >= 9 and current_hour < 17
}
EOF

# List Sentinel policies
vault list sys/policies/egp

# Read Sentinel policy
vault read sys/policies/egp/business-hours-only
```

### Control Groups

```bash
# Create control group policy
vault write sys/policies/acl/control-group-policy policy=@control-group.hcl

# Example control group policy (control-group.hcl)
cat > control-group.hcl <<'EOF'
path "secret/sensitive/*" {
  capabilities = ["read"]
  control_group = {
    factor "approvers" {
      identity {
        group_names = ["managers"]
        approvals = 2
      }
    }
  }
}
EOF

# Request access to controlled resource
vault read secret/sensitive/data
# Returns: control group request ID

# Approve request (as manager)
vault write sys/control-group/authorize \
  accessor=<control-group-accessor>
```

### MFA (Multi-Factor Authentication)

```bash
# Enable TOTP MFA
vault write sys/mfa/method/totp/my_totp \
  issuer=Vault \
  period=30 \
  key_size=20 \
  algorithm=SHA256 \
  digits=6

# Configure MFA for a path
vault write sys/mfa/login-enforcement/my_enforcement \
  mfa_method_ids=my_totp \
  auth_method_types=userpass

# Generate QR code for user
vault read sys/mfa/method/totp/my_totp/admin-generate \
  entity_id=<entity-id>
```

---

## High Availability Setup

### Raft Integrated Storage (Recommended)

```bash
# Node 1 Configuration
cat > /etc/vault.d/vault.hcl <<'EOF'
storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-node-1"
  
  retry_join {
    leader_api_addr = "https://vault-node-2:8200"
  }
  retry_join {
    leader_api_addr = "https://vault-node-3:8200"
  }
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = 0
  tls_cert_file = "/opt/vault/tls/vault-cert.pem"
  tls_key_file  = "/opt/vault/tls/vault-key.pem"
}

api_addr     = "https://vault-node-1:8200"
cluster_addr = "https://vault-node-1:8201"
ui = true
EOF

# Initialize on Node 1
vault operator init

# Join Node 2 and Node 3
# On Node 2:
vault operator raft join https://vault-node-1:8200

# On Node 3:
vault operator raft join https://vault-node-1:8200

# Check cluster status
vault operator raft list-peers
```

### Consul Storage Backend (Alternative)

```bash
# Install Consul first
# Then configure Vault to use Consul

cat > /etc/vault.d/vault.hcl <<'EOF'
storage "consul" {
  address = "127.0.0.1:8500"
  path    = "vault/"
  token   = "<consul-token>"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = 0
  tls_cert_file = "/opt/vault/tls/vault-cert.pem"
  tls_key_file  = "/opt/vault/tls/vault-key.pem"
}

api_addr     = "https://< IP-Address>:8200"
cluster_addr = "https://< IP-Address>:8201"
ui = true
EOF
```

---

## HSM Auto-Unseal

### PKCS#11 HSM Configuration

```bash
# Install HSM client libraries
# Example for SafeNet Luna HSM
sudo yum install -y luna-client

# Configure Vault for HSM auto-unseal
cat >> /etc/vault.d/vault.hcl <<'EOF'

seal "pkcs11" {
  lib            = "/usr/lib/libCryptoki2_64.so"
  slot           = "0"
  pin            = "AAAA-BBBB-CCCC-DDDD"
  key_label      = "vault-hsm-key"
  hmac_key_label = "vault-hsm-hmac-key"
  generate_key   = true
}
EOF

# Restart Vault
sudo systemctl restart vault

# Vault will now auto-unseal using HSM
vault status
# Should show: Sealed: false (without manual unseal)
```

### AWS KMS Auto-Unseal

```bash
# Configure AWS KMS auto-unseal
cat >> /etc/vault.d/vault.hcl <<'EOF'

seal "awskms" {
  region     = "us-east-1"
  kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  endpoint   = "https://kms.us-east-1.amazonaws.com"
}
EOF

# Set AWS credentials
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"

# Restart Vault
sudo systemctl restart vault
```

---

## Monitoring and Telemetry

### Prometheus Integration

```bash
# Enable Prometheus metrics
vault write sys/metrics/config \
  enabled=true \
  enable_hostname_label=true

# Prometheus scrape config
cat > prometheus.yml <<'EOF'
scrape_configs:
  - job_name: 'vault'
    metrics_path: '/v1/sys/metrics'
    params:
      format: ['prometheus']
    scheme: https
    tls_config:
      insecure_skip_verify: true
    static_configs:
      - targets: ['< IP-Address>:8200']
    bearer_token: '<vault-token>'
EOF
```

### Audit Logging

```bash
# Enable file audit device
vault audit enable file file_path=/opt/vault/logs/audit.log

# Enable syslog audit device
vault audit enable syslog tag="vault" facility="AUTH"

# Enable socket audit device
vault audit enable socket address="127.0.0.1:9090" socket_type="tcp"

# List audit devices
vault audit list
```

---

## Enterprise Best Practices

### 1. License Management

```bash
# Check license expiration
vault license get

# Set up license renewal alerts
# Monitor license expiration date
# Plan renewal 30 days before expiration
```

### 2. Namespace Strategy

```bash
# Organize by:
# - Business units
# - Environments (dev, staging, prod)
# - Applications
# - Teams

# Example structure:
# /engineering/dev
# /engineering/prod
# /finance/prod
# /operations/monitoring
```

### 3. Replication Strategy

```bash
# Primary cluster: Active-Active for performance
# DR cluster: Standby for disaster recovery
# Read replicas: For read-heavy workloads

# Monitor replication lag
vault read sys/replication/performance/status
vault read sys/replication/dr/status
```

### 4. Security Hardening

```bash
# Enable Sentinel policies for compliance
# Implement control groups for sensitive data
# Use MFA for privileged operations
# Enable audit logging on all clusters
# Rotate root tokens regularly
# Use HSM for auto-unseal in production
```

---

## Quick Reference

### Enterprise Commands

```bash
# License
vault license get
vault write sys/license text="<license>"

# Namespaces
vault namespace create <name>
vault namespace list
vault namespace delete <name>

# Replication
vault read sys/replication/status
vault write -f sys/replication/performance/primary/enable
vault write -f sys/replication/dr/primary/enable

# Sentinel
vault write sys/policies/egp/<name> policy=@policy.sentinel
vault list sys/policies/egp

# Control Groups
vault read sys/control-group/request
vault write sys/control-group/authorize accessor=<id>

# MFA
vault write sys/mfa/method/totp/<name> issuer=Vault
vault read sys/mfa/method/totp/<name>/admin-generate

# HSM
vault operator rekey -target=recovery
vault operator unseal -migrate
```

---

## Resources

- [Vault Enterprise Documentation](https://www.vaultproject.io/docs/enterprise)
- [Vault Enterprise Features](https://www.vaultproject.io/docs/enterprise/index.html)
- [Replication Guide](https://learn.hashicorp.com/tutorials/vault/replication-setup)
- [Namespaces Guide](https://learn.hashicorp.com/tutorials/vault/namespaces)
- [Sentinel Policies](https://learn.hashicorp.com/tutorials/vault/sentinel)
- [HSM Integration](https://learn.hashicorp.com/tutorials/vault/hsm-auto-unseal)

---

**Vault Enterprise Setup Complete! 🎉**

Your enterprise-grade Vault deployment is ready with advanced features for production use.
