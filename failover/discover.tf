# Resource group

data "ibm_resource_group" "resource_group" {
  name = "${var.prefix}-rg"
}

# DNS service, zone, and records

data "ibm_resource_instance" "dns_service" {
  name =  "${var.prefix}-dns"
}

data "ibm_dns_zones" "dns_zones" {
  instance_id = data.ibm_resource_instance.dns_service.guid
}

data "ibm_dns_resource_records" "dns_records" {
  instance_id = data.ibm_resource_instance.dns_service.guid
  zone_id     = local.dns_zones["example.com"].zone_id
}

# Discover account settings resource so that we can leverage a side effect:
# The ID of this resource is the same as our account ID

data "ibm_iam_account_settings" "settings" {
}

# VPC

data "ibm_is_vpc" "vpc" {
  name = "${var.prefix}-dr-vpc"
}

# VPC subnets

data "ibm_is_subnets" "subnets" {
  vpc = data.ibm_is_vpc.vpc.id
}

# Reserved IPs

data "ibm_is_subnet_reserved_ips" "reserved_ips_tier2_0" {
  subnet = local.subnets["${var.prefix}-dr-tier2-0"].id
}

data "ibm_is_subnet_reserved_ips" "reserved_ips_tier2_1" {
  subnet = local.subnets["${var.prefix}-dr-tier2-1"].id
}

# Default SG

data "ibm_is_security_group" "default_sg" {
  name = "${var.prefix}-dr-default-sg"
}

# Public Application Load Balancer

data "ibm_is_lb" "lb" {
  name = "${var.prefix}-dr-lb"
}

data "ibm_is_lb_pool" "pool" {
  lb   = data.ibm_is_lb.lb.id
  name = "${var.prefix}-dr-lb-pool"
}

# SSH key

data "ibm_is_ssh_key" "ssh_key_dr" {
  name = "${var.prefix}-dr-ssh"
}

# Volume snapshots

data "ibm_is_snapshots" "snapshots" {
}

# Calculate some resources

locals {
  primary_snapshots = { for s in data.ibm_is_snapshots.snapshots.snapshots : s.captured_at => s if s.lifecycle_state == "stable" && contains(s.tags, "${var.prefix}-primarybackup") }
  primary_snapshot = local.primary_snapshots[reverse(keys(local.primary_snapshots))[0]]

  standby_snapshots = { for s in data.ibm_is_snapshots.snapshots.snapshots : s.captured_at => s if s.lifecycle_state == "stable" && contains(s.tags, "${var.prefix}-standbybackup") }
  standby_snapshot = local.standby_snapshots[reverse(keys(local.standby_snapshots))[0]]

  subnets = { for s in data.ibm_is_subnets.subnets.subnets : s.name => s }
  reserved_ip_primary = [for i in data.ibm_is_subnet_reserved_ips.reserved_ips_tier2_0.reserved_ips : i if i.name == "${var.prefix}-dr-db-primary"][0]
  reserved_ip_standby = [for i in data.ibm_is_subnet_reserved_ips.reserved_ips_tier2_1.reserved_ips : i if i.name == "${var.prefix}-dr-db-standby"][0]

  dns_zones = { for z in data.ibm_dns_zones.dns_zones.dns_zones : z.name => z }
  dns_records = { for r in data.ibm_dns_resource_records.dns_records.dns_resource_records: r.name => r }
}

