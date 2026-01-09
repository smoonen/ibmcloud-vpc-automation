module "vpc_region1" {
  source = "./vpc_skeleton"

  ibmcloud_api_key  = var.ibmcloud_api_key
  region            = var.region
  prefix            = var.prefix
  network           = var.network
  allowed_ips       = var.allowed_ips
  dns_service_guid  = ibm_resource_instance.dns_service.guid
  dns_zone_id       = ibm_dns_zone.dns_zone.zone_id
  resource_group_id = ibm_resource_group.resource_group.id
}

# SSH key

resource "ibm_is_ssh_key" "ssh_key" {
  name           = "${var.prefix}-ssh"
  public_key     = var.ssh_authorized_key
  type           = "rsa"
  resource_group = ibm_resource_group.resource_group.id
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
      subnet          = module.vpc_region1.tier1_subnets[0].id
      #resource_group  = ibm_resource_group.resource_group.id # Not working currently
      security_groups = [module.vpc_region1.default_sg_id]
      auto_delete     = true
    }
  }

  vpc            = module.vpc_region1.vpc_id
  resource_group = ibm_resource_group.resource_group.id
  zone           = "${var.region}-1"
  keys           = [ibm_is_ssh_key.ssh_key.id]

  boot_volume {
    name                             = "${var.prefix}-tier1-boot"
    delete_volume_on_instance_delete = true
  }

  user_data = templatefile("${path.module}/templates/tier1_user_data.sh", {
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
  subnets           = [for subnet in module.vpc_region1.tier1_subnets : subnet.id]
  resource_group    = ibm_resource_group.resource_group.id

  load_balancer      = module.vpc_region1.lb.id
  load_balancer_pool = module.vpc_region1.lb_pool_id
  application_port   = 22

  depends_on         = [module.vpc_region1.lb_listener] # Needed for LB to be fully ready
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
      subnet          = module.vpc_region1.tier2_subnets[0].id
      resource_group  = ibm_resource_group.resource_group.id
      security_groups = [module.vpc_region1.default_sg_id]
      auto_delete     = true
    }
  }

  vpc            = module.vpc_region1.vpc_id
  resource_group = ibm_resource_group.resource_group.id
  zone           = "${var.region}-1"
  keys           = [ibm_is_ssh_key.ssh_key.id]
  tags           = ["${var.prefix}-primarybackup"]

  boot_volume {
    name               = "${var.prefix}-tier2-primary-boot"
    auto_delete_volume = true
    tags               = ["${var.prefix}-primarybackup"]
  }

  user_data = templatefile("${path.module}/templates/tier2_primary_init.sh", {
    subnets_tier1 = module.vpc_region1.tier1_subnets,
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
      subnet          = module.vpc_region1.tier2_subnets[1].id
      resource_group  = ibm_resource_group.resource_group.id
      security_groups = [module.vpc_region1.default_sg_id]
      auto_delete     = true
    }
  }

  vpc            = module.vpc_region1.vpc_id
  resource_group = ibm_resource_group.resource_group.id
  zone           = "${var.region}-2"
  keys           = [ibm_is_ssh_key.ssh_key.id]
  tags           = ["${var.prefix}-standbybackup"]

  boot_volume {
    name               = "${var.prefix}-tier2-standby-boot"
    auto_delete_volume = true
    tags               = ["${var.prefix}-standbybackup"]
  }

  user_data = templatefile("${path.module}/templates/tier2_standby_init.sh", {
    subnets_tier1 = module.vpc_region1.tier1_subnets,
    replication_password = var.replication_password
  })
}

# DNS records for application (CNAME to load balancer), primary, and secondary

resource "ibm_dns_resource_record" "app" {
  instance_id = ibm_resource_instance.dns_service.guid
  zone_id     = ibm_dns_zone.dns_zone.zone_id
  type        = "CNAME"
  name        = "app"
  rdata       = module.vpc_region1.lb.hostname
  ttl         = 300
}

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

