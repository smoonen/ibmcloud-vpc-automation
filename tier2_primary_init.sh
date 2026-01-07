#!/bin/bash
set -e

#############################################
# PostgreSQL Primary Server Setup Script
# Ubuntu 24.04
#############################################

# Configuration Variables
PRIMARY_HOST="db-primary.example.com"
STANDBY_HOST="db-standby.example.com"
REPLICATION_USER="replicator"
REPLICATION_PASSWORD='${replication_password}'
POSTGRES_VERSION="16"
DATA_DIR="/var/lib/postgresql/$${POSTGRES_VERSION}/main"
CONFIG_DIR="/etc/postgresql/$${POSTGRES_VERSION}/main"

# Allow-list configuration for test database
ALLOWED_USER="appuser"
ALLOWED_SUBNET1="${subnets_tier1[0].cidr}"
ALLOWED_SUBNET2="${subnets_tier1[1].cidr}"
ALLOWED_SUBNET3="${subnets_tier1[2].cidr}"

# Logging
LOG_FILE="/var/log/postgresql_primary_setup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "=========================================="
echo "PostgreSQL Primary Server Setup"
echo "Started at: $(date)"
echo "=========================================="

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

# Set hostname
hostnamectl hostname $PRIMARY_HOST

# Resolve standby hostname
STANDBY_IP=""
while [[ -z "$${STANDBY_IP}" ]]; do
  # getent may return multiple addresses; take the first IPv4
  STANDBY_IP="$(getent ahostsv4 "$${STANDBY_HOST}" 2>/dev/null \
                | awk 'NR==1{print $1}')"

  if [[ -z "$${STANDBY_IP}" ]]; then
    sleep 5
  fi
done

# Update system
echo "Updating system packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install PostgreSQL
echo "Installing PostgreSQL $${POSTGRES_VERSION}..."
apt-get install -y postgresql-$${POSTGRES_VERSION} postgresql-contrib-$${POSTGRES_VERSION}

# Wait for PostgreSQL to start
echo "Waiting for PostgreSQL to start..."
for i in {1..30}; do
    if systemctl is-active --quiet postgresql; then
        echo "PostgreSQL is running"
        break
    fi
    echo "Waiting for PostgreSQL... attempt $i/30"
    sleep 2
done

# Create a test database
echo "Creating test database..."
sudo -u postgres psql <<EOF
CREATE DATABASE testdb;
\c testdb
CREATE TABLE test_replication (
    id SERIAL PRIMARY KEY,
    message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO test_replication (message) VALUES ('Primary server initialized');
EOF

# Create allowed user for test database
echo "Creating allowed user for test database..."
sudo -u postgres psql <<EOF
-- Create user
CREATE ROLE $${ALLOWED_USER} WITH LOGIN;

-- Grant privileges on testdb
GRANT CONNECT ON DATABASE testdb TO $${ALLOWED_USER};
\c testdb
GRANT USAGE ON SCHEMA public TO $${ALLOWED_USER};
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO $${ALLOWED_USER};
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO $${ALLOWED_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO $${ALLOWED_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO $${ALLOWED_USER};
EOF

# Create replication user and slot
echo "Creating replication user and slot..."
sudo -u postgres psql <<EOF
-- Create replication user
CREATE ROLE $${REPLICATION_USER} WITH REPLICATION LOGIN PASSWORD '$${REPLICATION_PASSWORD}';

-- Create replication slot for standby
SELECT pg_create_physical_replication_slot('standby1_slot');
EOF

# Stop PostgreSQL for configuration
echo "Stopping PostgreSQL for configuration..."
systemctl stop postgresql

# Configure PostgreSQL for replication
echo "Configuring PostgreSQL as primary server..."

# Backup original configuration
cp "$${CONFIG_DIR}/postgresql.conf" "$${CONFIG_DIR}/postgresql.conf.backup"
cp "$${CONFIG_DIR}/pg_hba.conf" "$${CONFIG_DIR}/pg_hba.conf.backup"

# Configure postgresql.conf
cat >> "$${CONFIG_DIR}/postgresql.conf" <<EOF

# Replication Settings (Primary)
listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 1GB
hot_standby = on
archive_mode = on
archive_command = '/bin/true'
synchronous_commit = on
synchronous_standby_names = 'standby1'
EOF

# Configure pg_hba.conf for replication and allow-list
echo "Configuring pg_hba.conf for replication and allow-list..."
cat >> "$${CONFIG_DIR}/pg_hba.conf" <<EOF

# Allow-list: Trust authentication for specific user/subnet/database
host    testdb          $${ALLOWED_USER}         $${ALLOWED_SUBNET1}       trust
host    testdb          $${ALLOWED_USER}         $${ALLOWED_SUBNET2}       trust
host    testdb          $${ALLOWED_USER}         $${ALLOWED_SUBNET3}       trust

# Replication connections
host    replication     $${REPLICATION_USER}     $${STANDBY_IP}/32        scram-sha-256
host    all             all                     $${STANDBY_IP}/32        scram-sha-256
EOF

# Start PostgreSQL
echo "Starting PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to accept connections..."
for i in {1..60}; do
    if sudo -u postgres psql -c "SELECT 1" > /dev/null 2>&1; then
        echo "PostgreSQL is accepting connections"
        break
    fi
    echo "Waiting for PostgreSQL to be ready... attempt $i/60"
    sleep 2
done

# Verify replication configuration
echo "Verifying replication configuration..."
sudo -u postgres psql -c "SELECT * FROM pg_replication_slots;"
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"

echo "=========================================="
echo "Primary PostgreSQL Server Setup Complete"
echo "Completed at: $(date)"
echo "=========================================="
echo ""
echo "Server Information:"
echo "  - Primary: $${PRIMARY_HOST}"
echo "  - PostgreSQL Version: $${POSTGRES_VERSION}"
echo "  - Data Directory: $${DATA_DIR}"
echo "  - Replication User: $${REPLICATION_USER}"
echo ""
echo "Allow-list Configuration:"
echo "  - Allowed User: $${ALLOWED_USER}"
echo "  - Allowed Subnets: $${ALLOWED_SUBNET1}, $${ALLOWED_SUBNET2}, $${ALLOWED_SUBNET3}"
echo "  - Database: testdb"
echo "  - Authentication: trust (no password required)"
echo ""
echo "Next Steps:"
echo "  1. Run the standby server setup script on $${STANDBY_HOST}"
echo "  2. View logs: tail -f $${LOG_FILE}"
echo ""
echo "To verify replication after standby is set up:"
echo "  sudo -u postgres psql -c \"SELECT * FROM pg_stat_replication;\""
echo ""
echo "To test allow-list access from allowed subnet:"
echo "  psql -h $${PRIMARY_HOST} -U $${ALLOWED_USER} -d testdb"

