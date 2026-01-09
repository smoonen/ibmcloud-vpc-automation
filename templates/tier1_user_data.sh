#!/bin/bash
set -e

# Wait for network to be ready
echo "Waiting for network to be ready..."
for i in {1..30}; do
    if ip addr show | grep -q "inet.*scope global"; then
        echo "Network is ready"
        break
    fi
    echo "Waiting for network... attempt $i/30"
    sleep 2
done

# Generate consistent host keys across the tier 1 servers so that we can connect to them through the LB interchangeably
cat > /etc/ssh/ssh_host_ecdsa_key << 'EOF'
${ecdsa_private_key}
EOF

cat > /etc/ssh/ssh_host_ecdsa_key.pub << 'EOF'
${ecdsa_public_key}
EOF

cat > /etc/ssh/ssh_host_ed25519_key << 'EOF'
${ed25519_private_key}
EOF

cat > /etc/ssh/ssh_host_ed25519_key.pub << 'EOF'
${ed25519_public_key}
EOF

cat > /etc/ssh/ssh_host_rsa_key << 'EOF'
${rsa_private_key}
EOF

cat > /etc/ssh/ssh_host_rsa_key.pub << 'EOF'
${rsa_public_key}
EOF

# Restart sshd
systemctl restart ssh.service

# Update system
echo "Updating system packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install PostgreSQL
POSTGRES_VERSION="16"
echo "Installing PostgreSQL $${POSTGRES_VERSION}..."
apt-get install -y postgresql-$${POSTGRES_VERSION} postgresql-contrib-$${POSTGRES_VERSION}

