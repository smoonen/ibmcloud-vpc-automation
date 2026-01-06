#!/bin/bash

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

