#!/bin/bash
set -e

#############################################
# PostgreSQL Standby Server Setup Script
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

# Logging
LOG_FILE="/var/log/postgresql_standby_setup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "=========================================="
echo "PostgreSQL Standby Server Setup"
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
hostnamectl hostname $STANDBY_HOST

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

# Stop PostgreSQL immediately after installation
echo "Stopping PostgreSQL..."
systemctl stop postgresql

# Wait for primary server to be ready
echo "Waiting for primary server at $${PRIMARY_HOST} to be ready..."
PRIMARY_READY=false
for i in {1..120}; do
    if pg_isready -h $${PRIMARY_HOST} -p 5432 -U postgres > /dev/null 2>&1; then
        echo "Primary server is ready"
        PRIMARY_READY=true
        break
    fi
    echo "Waiting for primary server... attempt $i/120 (will retry for 10 minutes)"
    sleep 5
done

if [ "$PRIMARY_READY" = false ]; then
    echo "ERROR: Primary server at $${PRIMARY_HOST} is not ready after 10 minutes"
    echo "Please ensure the primary server is running and accessible"
    exit 1
fi

# Test replication user connectivity
echo "Testing replication user connectivity..."
REPLICATION_READY=false
for i in {1..60}; do
    if PGPASSWORD="$${REPLICATION_PASSWORD}" psql -h $${PRIMARY_HOST} -U $${REPLICATION_USER} -d postgres -c "SELECT 1" > /dev/null 2>&1; then
        echo "Replication user is accessible"
        REPLICATION_READY=true
        break
    fi
    echo "Waiting for replication user to be ready... attempt $i/60"
    sleep 5
done

if [ "$REPLICATION_READY" = false ]; then
    echo "ERROR: Cannot connect to primary server with replication user"
    echo "Please verify the replication user exists on the primary server"
    exit 1
fi

# Verify replication slot exists
echo "Verifying replication slot on primary..."
SLOT_EXISTS=false
for i in {1..30}; do
    if PGPASSWORD="$${REPLICATION_PASSWORD}" psql -h $${PRIMARY_HOST} -U $${REPLICATION_USER} -d postgres -t -c "SELECT slot_name FROM pg_replication_slots WHERE slot_name='standby1_slot';" | grep -q "standby1_slot"; then
        echo "Replication slot 'standby1_slot' exists on primary"
        SLOT_EXISTS=true
        break
    fi
    echo "Waiting for replication slot... attempt $i/30"
    sleep 2
done

if [ "$SLOT_EXISTS" = false ]; then
    echo "WARNING: Replication slot 'standby1_slot' not found on primary"
    echo "Continuing anyway - slot may be created later"
fi

# Remove existing data directory
echo "Removing existing data directory..."
rm -rf $${DATA_DIR}/*

# Create .pgpass file for passwordless replication
echo "Creating .pgpass file for postgres user..."
sudo -u postgres bash <<EOF
cat > ~/.pgpass <<PGPASS
$${PRIMARY_HOST}:5432:replication:$${REPLICATION_USER}:$${REPLICATION_PASSWORD}
$${PRIMARY_HOST}:5432:*:$${REPLICATION_USER}:$${REPLICATION_PASSWORD}
PGPASS
chmod 0600 ~/.pgpass
EOF

# Perform base backup from primary
echo "Performing base backup from primary server..."
sudo -u postgres pg_basebackup -h $${PRIMARY_HOST} -D $${DATA_DIR} -U $${REPLICATION_USER} -v -P -W -R -X stream -S standby1_slot --no-password

# Verify base backup
if [ ! -f "$${DATA_DIR}/PG_VERSION" ]; then
    echo "ERROR: Base backup failed - data directory is incomplete"
    exit 1
fi

echo "Base backup completed successfully"

# Configure standby-specific settings
echo "Configuring standby-specific settings..."

# The -R flag in pg_basebackup creates standby.signal and configures primary_conninfo
# We'll verify and adjust if needed

# Backup the auto-generated postgresql.auto.conf
if [ -f "$${DATA_DIR}/postgresql.auto.conf" ]; then
    cp "$${DATA_DIR}/postgresql.auto.conf" "$${DATA_DIR}/postgresql.auto.conf.backup"
fi

# Add standby-specific configuration
cat >> "$${CONFIG_DIR}/postgresql.conf" <<EOF

# Standby Server Settings
hot_standby = on
primary_slot_name = 'standby1_slot'
restore_command = '/bin/true'
recovery_target_timeline = 'latest'
EOF

# Ensure standby.signal exists (created by pg_basebackup -R)
if [ ! -f "$${DATA_DIR}/standby.signal" ]; then
    echo "Creating standby.signal file..."
    sudo -u postgres touch "$${DATA_DIR}/standby.signal"
fi

# Verify primary_conninfo in postgresql.auto.conf
echo "Verifying replication connection string..."
if ! grep -q "primary_conninfo" "$${DATA_DIR}/postgresql.auto.conf" 2>/dev/null; then
    echo "Adding primary_conninfo to postgresql.auto.conf..."
    sudo -u postgres bash <<EOF
cat >> $${DATA_DIR}/postgresql.auto.conf <<AUTOCONF
primary_conninfo = 'host=$${PRIMARY_HOST} port=5432 user=$${REPLICATION_USER} password=$${REPLICATION_PASSWORD} application_name=standby1'
AUTOCONF
EOF
fi

# Set proper permissions
chown -R postgres:postgres $${DATA_DIR}
chmod 0700 $${DATA_DIR}

# Start PostgreSQL
echo "Starting PostgreSQL in standby mode..."
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

# Verify standby status
echo "Verifying standby status..."
sleep 5

RECOVERY_STATUS=$(sudo -u postgres psql -t -c "SELECT pg_is_in_recovery();")
if echo "$RECOVERY_STATUS" | grep -q "t"; then
    echo "SUCCESS: Server is in recovery mode (standby)"
else
    echo "WARNING: Server is not in recovery mode - may not be properly configured as standby"
fi

echo "=========================================="
echo "Standby PostgreSQL Server Setup Complete"
echo "Completed at: $(date)"
echo "=========================================="
echo ""
echo "Server Information:"
echo "  - Standby: $${STANDBY_HOST}"
echo "  - Primary: $${PRIMARY_HOST}"
echo "  - PostgreSQL Version: $${POSTGRES_VERSION}"
echo "  - Data Directory: $${DATA_DIR}"
echo ""
echo "Verification Commands:"
echo "  - View logs: tail -f $${LOG_FILE}"
echo "  - Check if in recovery: sudo -u postgres psql -c \"SELECT pg_is_in_recovery();\""
echo ""
echo "To test replication:"
echo "  1. On primary: sudo -u postgres psql testdb -c \"INSERT INTO test_replication (message) VALUES ('Test from primary');\""
echo "  2. On standby: sudo -u postgres psql testdb -c \"SELECT * FROM test_replication;\""

