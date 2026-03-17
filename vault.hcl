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
