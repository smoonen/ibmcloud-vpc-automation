# VPC

resource "ibm_is_vpc" "vpc" {
  name                        = "${var.prefix}-vpc"
  resource_group              = var.resource_group_id
  address_prefix_management   = "manual"
  default_network_acl_name    = "${var.prefix}-default-acl"
  default_security_group_name = "${var.prefix}-default-sg"
  default_routing_table_name  = "${var.prefix}-default-rt"
}

# VPC address prefixes, subnets, and public gateways

locals {
  prefixes = {
    for zone_number in range(3) : zone_number => {
      cidr = cidrsubnet(var.network, 2, zone_number)
      zone = "${var.region}-${zone_number + 1}"
    }
  }
  subnets_tier1 = {
    for zone_number in range(3) : zone_number => {
      cidr = cidrsubnet(local.prefixes[zone_number].cidr, 1, 0)
      zone = local.prefixes[zone_number].zone
    }
  }
  subnets_tier2 = {
    for zone_number in range(3) : zone_number => {
      cidr = cidrsubnet(local.prefixes[zone_number].cidr, 1, 1)
      zone = local.prefixes[zone_number].zone
    }
  }
}

resource "ibm_is_vpc_address_prefix" "address_prefixes" {
  for_each = local.prefixes
  name     = "${var.prefix}-pfx-${each.key}"
  zone     = each.value.zone
  vpc      = ibm_is_vpc.vpc.id
  cidr     = each.value.cidr
}

resource "ibm_is_public_gateway" "public_gateways" {
  for_each        = local.prefixes
  name            = "${var.prefix}-pgw-${each.key}"
  resource_group  = var.resource_group_id
  vpc             = ibm_is_vpc.vpc.id
  zone            = each.value.zone
}

resource "ibm_is_subnet" "subnets_tier1" {
  for_each        = local.subnets_tier1
  name            = "${var.prefix}-tier1-${each.key}"
  resource_group  = var.resource_group_id
  vpc             = ibm_is_vpc.vpc.id
  zone            = each.value.zone
  ipv4_cidr_block = each.value.cidr
  public_gateway = ibm_is_public_gateway.public_gateways[each.key].id
}

resource "ibm_is_subnet" "subnets_tier2" {
  for_each        = local.subnets_tier2
  name            = "${var.prefix}-tier2-${each.key}"
  resource_group  = var.resource_group_id
  vpc             = ibm_is_vpc.vpc.id
  zone            = each.value.zone
  ipv4_cidr_block = each.value.cidr
  public_gateway = ibm_is_public_gateway.public_gateways[each.key].id
}

# Connect VPC to DNS as a permitted network

resource "ibm_dns_permitted_network" "dns_zone_permitted_network" {
  instance_id = var.dns_service_guid
  zone_id     = var.dns_zone_id
  vpc_crn     = ibm_is_vpc.vpc.crn
}

# Inbound security group; also harvest default SG

resource "ibm_is_security_group" "inbound_sg" {
  name           = "${var.prefix}-inbound-sg"
  vpc            = ibm_is_vpc.vpc.id
  resource_group = var.resource_group_id
}

resource "ibm_is_security_group_rule" "inbound_sg_rules" {
  for_each  = var.allowed_ips
  group     = ibm_is_security_group.inbound_sg.id
  direction = "inbound"
  remote    = each.value
  tcp {
    port_min = 22
    port_max = 22
  }
}

data "ibm_is_security_group" "default_sg" {
  name = "${var.prefix}-default-sg"
  depends_on = [ibm_is_vpc.vpc]
}

# Public Application Load Balancer

resource "ibm_is_lb" "lb" {
  name            = "${var.prefix}-lb"
  subnets         = [for subnet in ibm_is_subnet.subnets_tier1 : subnet.id]
  type            = "public"
  resource_group  = var.resource_group_id
  security_groups = [ibm_is_security_group.inbound_sg.id, data.ibm_is_security_group.default_sg.id]
}

resource "ibm_is_lb_pool" "pool" {
  name                = "${var.prefix}-lb-pool"
  lb                  = ibm_is_lb.lb.id
  algorithm           = "round_robin"
  protocol            = "tcp"
  health_delay        = 5
  health_retries      = 2
  health_timeout      = 2
  health_type         = "tcp"
  health_monitor_port = 22
}

resource "ibm_is_lb_listener" "listener" {
  lb           = ibm_is_lb.lb.id
  port         = 22
  protocol     = "tcp"
  default_pool = ibm_is_lb_pool.pool.pool_id
}

