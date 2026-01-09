# Instance templates, groups, and group configuration (managers, scaling policies) for tier 1 VSIs.
# Although an instance template belongs to a specific subnet and zone, you can associate multiple
#   subnets with an instance group. The group will override those subnets resulting in the ability
#   to deploy instances across multiple zones.

data "ibm_is_image" "ubuntu" {
  name = "ibm-ubuntu-24-04-3-minimal-amd64-4"
}

resource "ibm_is_instance_template" "template" {
  name    = "${var.prefix}-dr-template"
  image   = data.ibm_is_image.ubuntu.id
  profile = "bxf-2x8"

  primary_network_attachment {
    name   = "eth0"
    virtual_network_interface {
      name            = "${var.prefix}-dr-vni-tier1"
      subnet          = local.subnets["${var.prefix}-dr-tier1-0"].id
      #resource_group  = ibm_resource_group.resource_group.id # Not working currently
      security_groups = [data.ibm_is_security_group.default_sg.id]
      auto_delete     = true
    }
  }

  vpc            = data.ibm_is_vpc.vpc.id
  resource_group = data.ibm_resource_group.resource_group.id
  zone           = "${var.secondary_region}-1"
  keys           = [data.ibm_is_ssh_key.ssh_key_dr.id]

  boot_volume {
    name                             = "${var.prefix}-dr-tier1-boot"
    delete_volume_on_instance_delete = true
  }

  user_data = templatefile("${path.module}/../templates/tier1_user_data.sh", {
    ecdsa_private_key = var.ecdsa_private_key
    ecdsa_public_key = var.ecdsa_public_key
    ed25519_private_key = var.ed25519_private_key
    ed25519_public_key = var.ed25519_public_key
    rsa_private_key = var.rsa_private_key
    rsa_public_key = var.rsa_public_key
  })
}

resource "ibm_is_instance_group" "instance_group" {
  name              = "${var.prefix}-dr-tier1"
  instance_template = ibm_is_instance_template.template.id
  instance_count    = 3
  subnets           = [for zone_number in range(3) : local.subnets["${var.prefix}-dr-tier1-${zone_number}"].id]
  resource_group    = data.ibm_resource_group.resource_group.id

  load_balancer      = data.ibm_is_lb.lb.id
  load_balancer_pool = data.ibm_is_lb_pool.pool.id
  application_port   = 22
}

resource "ibm_is_instance_group_manager" "manager" {
  name               = "${var.prefix}-dr-tier1-mgr"
  instance_group     = ibm_is_instance_group.instance_group.id
  manager_type       = "autoscale"
  max_membership_count = 15
  min_membership_count = 3
  aggregation_window = 90
  cooldown           = 300
}

resource "ibm_is_instance_group_manager_policy" "expected_cpu" {
  name                = "${var.prefix}-dr-cpu"
  instance_group      = ibm_is_instance_group.instance_group.id
  instance_group_manager = ibm_is_instance_group_manager.manager.manager_id
  metric_type         = "cpu"
  metric_value        = 85
  policy_type         = "target"
}

# Instance configuration for tier 2 VSIs. There will be a primary and a standby database server.

resource "ibm_is_instance" "db_primary" {
  name    = "${var.prefix}-dr-tier2-primary"
  profile = "bxf-2x8"

  primary_network_attachment {
    name   = "eth0"
    virtual_network_interface {
      name            = "${var.prefix}-dr-vni-tier2-primary"
      subnet          = local.subnets["${var.prefix}-dr-tier2-0"].id
      resource_group  = data.ibm_resource_group.resource_group.id
      security_groups = [data.ibm_is_security_group.default_sg.id]
      auto_delete     = true

      primary_ip {
        #address = local.reserved_ip_primary.address
        reserved_ip = local.reserved_ip_primary.reserved_ip
      }
    }
  }

  vpc            = data.ibm_is_vpc.vpc.id
  resource_group = data.ibm_resource_group.resource_group.id
  zone           = "${var.secondary_region}-1"
  keys           = [data.ibm_is_ssh_key.ssh_key_dr.id]
  tags           = ["${var.prefix}-primarybackup"]

  boot_volume {
    name               = "${var.prefix}-tier2-primary-boot"
    auto_delete_volume = true
    tags               = ["${var.prefix}-primarybackup"]
    snapshot           = local.primary_snapshot.id
  }
}

resource "ibm_is_instance" "db_standby" {
  name    = "${var.prefix}-dr-tier2-standby"
  profile = "bxf-2x8"

  primary_network_attachment {
    name   = "eth0"
    virtual_network_interface {
      name            = "${var.prefix}-dr-vni-tier2-standby"
      subnet          = local.subnets["${var.prefix}-dr-tier2-1"].id
      resource_group  = data.ibm_resource_group.resource_group.id
      security_groups = [data.ibm_is_security_group.default_sg.id]
      auto_delete     = true

      primary_ip {
        #address = local.reserved_ip_standby.address
        reserved_ip = local.reserved_ip_standby.reserved_ip
      }
    }
  }

  vpc            = data.ibm_is_vpc.vpc.id
  resource_group = data.ibm_resource_group.resource_group.id
  zone           = "${var.secondary_region}-2"
  keys           = [data.ibm_is_ssh_key.ssh_key_dr.id]
  tags           = ["${var.prefix}-standbybackup"]

  boot_volume {
    name               = "${var.prefix}-tier2-standby-boot"
    auto_delete_volume = true
    tags               = ["${var.prefix}-standbybackup"]
    snapshot           = local.standby_snapshot.id
  }
}

# DNS records for application (CNAME to load balancer), primary, and secondary

resource "ibm_dns_resource_record" "app" {
  instance_id = data.ibm_resource_instance.dns_service.guid
  zone_id     = local.dns_zones["example.com"].zone_id
  type        = "CNAME"
  name        = "app"
  rdata       = data.ibm_is_lb.lb.hostname
  ttl         = 300
}

resource "ibm_dns_resource_record" "db_primary" {
  instance_id = data.ibm_resource_instance.dns_service.guid
  zone_id     = local.dns_zones["example.com"].zone_id
  type        = "A"
  name        = "db-primary"
  rdata       = ibm_is_instance.db_primary.primary_network_attachment[0].primary_ip[0].address
  ttl         = 300
}

resource "ibm_dns_resource_record" "db_standby" {
  instance_id = data.ibm_resource_instance.dns_service.guid
  zone_id     = local.dns_zones["example.com"].zone_id
  type        = "A"
  name        = "db-standby"
  rdata       = ibm_is_instance.db_standby.primary_network_attachment[0].primary_ip[0].address
  ttl         = 300
}

