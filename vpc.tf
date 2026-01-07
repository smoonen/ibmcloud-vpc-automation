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

# Public Application Load Balancer

resource "ibm_is_lb" "lb" {
  name            = "${var.prefix}-lb"
  subnets         = [for subnet in ibm_is_subnet.subnets_tier1 : subnet.id]
  type            = "public"
  resource_group  = ibm_resource_group.resource_group.id
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

# Instance templates, groups, and group configuration (managers, scaling policies) for tier 1 VSIs.
# Although an instance template belongs to a specific subnet and zone, you can associate multiple
#   subnets with an instance group. The group will override those subnets resulting in the ability
#   to deploy instances across multiple zones.

data "ibm_is_image" "ubuntu" {
  name = "ibm-ubuntu-24-04-3-minimal-amd64-4"
}

resource "ibm_is_instance_template" "template" {
  name    = "${var.prefix}-template"
  image   = data.ibm_is_image.ubuntu.id
  profile = "bxf-2x8"

  primary_network_attachment {
    name   = "eth0"
    virtual_network_interface {
      name            = "${var.prefix}-vni-tier1"
      subnet          = ibm_is_subnet.subnets_tier1[0].id
      #resource_group  = ibm_resource_group.resource_group.id # Not working currently
      security_groups = [data.ibm_is_security_group.default_sg.id]
      auto_delete     = true
    }
  }

  vpc            = ibm_is_vpc.vpc.id
  resource_group = ibm_resource_group.resource_group.id
  zone           = "${var.region}-1"
  keys           = [ibm_is_ssh_key.ssh_key.id]

  boot_volume {
    name                             = "${var.prefix}-tier1-boot"
    delete_volume_on_instance_delete = true
  }

  user_data = templatefile("${path.module}/tier1_user_data.sh", {
    ecdsa_private_key = var.ecdsa_private_key
    ecdsa_public_key = var.ecdsa_public_key
    ed25519_private_key = var.ed25519_private_key
    ed25519_public_key = var.ed25519_public_key
    rsa_private_key = var.rsa_private_key
    rsa_public_key = var.rsa_public_key
  })
}

resource "ibm_is_instance_group" "instance_group" {
  name              = "${var.prefix}-tier1"
  instance_template = ibm_is_instance_template.template.id
  instance_count    = 3
  subnets           = [for subnet in ibm_is_subnet.subnets_tier1 : subnet.id]
  resource_group    = ibm_resource_group.resource_group.id

  load_balancer      = ibm_is_lb.lb.id
  load_balancer_pool = ibm_is_lb_pool.pool.pool_id
  application_port   = 22

  depends_on         = [ibm_is_lb_listener.listener] # Needed for LB to be fully ready
}

resource "ibm_is_instance_group_manager" "manager" {
  name               = "${var.prefix}-tier1-mgr"
  instance_group     = ibm_is_instance_group.instance_group.id
  manager_type       = "autoscale"
  max_membership_count = 15
  min_membership_count = 3
  aggregation_window = 90
  cooldown           = 300
}

resource "ibm_is_instance_group_manager_policy" "expected_cpu" {
  name                = "${var.prefix}-cpu"
  instance_group      = ibm_is_instance_group.instance_group.id
  instance_group_manager = ibm_is_instance_group_manager.manager.manager_id
  metric_type         = "cpu"
  metric_value        = 85
  policy_type         = "target"
}

# Instance configuration for tier 2 VSIs. There will be a primary and a standby database server.
resource "ibm_is_instance" "db_primary" {
  name    = "${var.prefix}-tier2-primary"
  image   = data.ibm_is_image.ubuntu.id
  profile = "bxf-2x8"

  primary_network_attachment {
    name   = "eth0"
    virtual_network_interface {
      name            = "${var.prefix}-vni-tier2-primary"
      subnet          = ibm_is_subnet.subnets_tier2[0].id
      resource_group  = ibm_resource_group.resource_group.id
      security_groups = [data.ibm_is_security_group.default_sg.id]
      auto_delete     = true
    }
  }

  vpc            = ibm_is_vpc.vpc.id
  resource_group = ibm_resource_group.resource_group.id
  zone           = "${var.region}-1"
  keys           = [ibm_is_ssh_key.ssh_key.id]

  boot_volume {
    name               = "${var.prefix}-tier2-primary-boot"
    auto_delete_volume = true
  }

  user_data = templatefile("${path.module}/tier2_primary_init.sh", {
    subnets_tier1 = local.subnets_tier1,
    replication_password = var.replication_password
  })
}

resource "ibm_is_instance" "db_standby" {
  name    = "${var.prefix}-tier2-standby"
  image   = data.ibm_is_image.ubuntu.id
  profile = "bxf-2x8"

  primary_network_attachment {
    name   = "eth0"
    virtual_network_interface {
      name            = "${var.prefix}-vni-tier2-standby"
      subnet          = ibm_is_subnet.subnets_tier2[1].id
      resource_group  = ibm_resource_group.resource_group.id
      security_groups = [data.ibm_is_security_group.default_sg.id]
      auto_delete     = true
    }
  }

  vpc            = ibm_is_vpc.vpc.id
  resource_group = ibm_resource_group.resource_group.id
  zone           = "${var.region}-2"
  keys           = [ibm_is_ssh_key.ssh_key.id]

  boot_volume {
    name               = "${var.prefix}-tier2-standby-boot"
    auto_delete_volume = true
  }

  user_data = templatefile("${path.module}/tier2_standby_init.sh", {
    subnets_tier1 = local.subnets_tier1,
    replication_password = var.replication_password
  })
}

# DNS records for primary and secondary
resource "ibm_dns_resource_record" "db_primary" {
  instance_id = ibm_resource_instance.dns_service.guid
  zone_id     = ibm_dns_zone.dns_zone.zone_id
  type        = "A"
  name        = "db-primary"
  rdata       = ibm_is_instance.db_primary.primary_network_attachment[0].primary_ip[0].address
  ttl         = 300
}

resource "ibm_dns_resource_record" "db_standby" {
  instance_id = ibm_resource_instance.dns_service.guid
  zone_id     = ibm_dns_zone.dns_zone.zone_id
  type        = "A"
  name        = "db-standby"
  rdata       = ibm_is_instance.db_standby.primary_network_attachment[0].primary_ip[0].address
  ttl         = 300
}

