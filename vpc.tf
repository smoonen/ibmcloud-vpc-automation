# Resource group
resource "ibm_resource_group" "resource_group" {
  name = "${var.prefix}-rg"
}

# DNS service and zone
resource "ibm_resource_instance" "dns_service" {
  name               =  "${var.prefix}-dns"
  resource_group_id  =  ibm_resource_group.resource_group.id
  location           =  "global"
  service            =  "dns-svcs"
  plan               =  "standard-dns"
}

resource "ibm_dns_zone" "dns_zone" {
  name        = "example.com"
  instance_id = ibm_resource_instance.dns_service.guid
}

# VPC itself

resource "ibm_is_vpc" "vpc" {
  name                        = "${var.prefix}-vpc"
  resource_group              = ibm_resource_group.resource_group.id
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
  resource_group  = ibm_resource_group.resource_group.id
  vpc             = ibm_is_vpc.vpc.id
  zone            = each.value.zone
}

resource "ibm_is_subnet" "subnets_tier1" {
  for_each        = local.subnets_tier1
  name            = "${var.prefix}-tier1-${each.key}"
  resource_group  = ibm_resource_group.resource_group.id
  vpc             = ibm_is_vpc.vpc.id
  zone            = each.value.zone
  ipv4_cidr_block = each.value.cidr
  public_gateway = ibm_is_public_gateway.public_gateways[each.key].id
}

resource "ibm_is_subnet" "subnets_tier2" {
  for_each        = local.subnets_tier2
  name            = "${var.prefix}-tier2-${each.key}"
  resource_group  = ibm_resource_group.resource_group.id
  vpc             = ibm_is_vpc.vpc.id
  zone            = each.value.zone
  ipv4_cidr_block = each.value.cidr
  public_gateway = ibm_is_public_gateway.public_gateways[each.key].id
}

# Connect VPC to DNS as a permitted network

resource "ibm_dns_permitted_network" "dns_zone_permitted_network" {
  instance_id = ibm_resource_instance.dns_service.guid
  zone_id     = ibm_dns_zone.dns_zone.zone_id
  vpc_crn     = ibm_is_vpc.vpc.crn
}

# SSH key

resource "ibm_is_ssh_key" "ssh_key" {
  name           = "${var.prefix}-ssh"
  public_key     = var.ssh_authorized_key
  type           = "rsa"
  resource_group = ibm_resource_group.resource_group.id
}

# Inbound security group; also harvest default SG

resource "ibm_is_security_group" "inbound_sg" {
  name           = "${var.prefix}-inbound-sg"
  vpc            = ibm_is_vpc.vpc.id
  resource_group = ibm_resource_group.resource_group.id
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

# Create instance templates for tier 1 VSIs

data "ibm_is_image" "ubuntu" {
  name = "ibm-ubuntu-24-04-3-minimal-amd64-4"
}

resource "ibm_is_instance_template" "templates" {
  for_each = local.subnets_tier1

  name    = "${var.prefix}-template-${each.key}"
  image   = data.ibm_is_image.ubuntu.id
  profile = "bxf-2x8"

  primary_network_attachment {
    name   = "eth0"
    virtual_network_interface {
      name            = "${var.prefix}-vni-tier1"
      subnet          = ibm_is_subnet.subnets_tier1[each.key].id
      resource_group  = ibm_resource_group.resource_group.id
      security_groups = [ibm_is_security_group.inbound_sg.id, data.ibm_is_security_group.default_sg.id]
      auto_delete     = true
    }
  }

  vpc            = ibm_is_vpc.vpc.id
  resource_group = ibm_resource_group.resource_group.id
  zone           = each.value.zone
  keys           = [ibm_is_ssh_key.ssh_key.id]

  boot_volume {
    name                             = "${var.prefix}-tier1-boot"
    delete_volume_on_instance_delete = true
  }
}

