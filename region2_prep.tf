module "vpc_region2" {
  source = "./vpc_skeleton"

  ibmcloud_api_key  = var.ibmcloud_api_key
  region            = var.secondary_region
  prefix            = "${var.prefix}-dr"
  network           = var.network
  allowed_ips       = var.allowed_ips
  dns_service_guid  = ibm_resource_instance.dns_service.guid
  dns_zone_id       = ibm_dns_zone.dns_zone.zone_id
  resource_group_id = ibm_resource_group.resource_group.id
}

# SSH key

resource "ibm_is_ssh_key" "ssh_key_dr" {
  provider       = ibm.secondary_region

  name           = "${var.prefix}-dr-ssh"
  public_key     = var.ssh_authorized_key
  type           = "rsa"
  resource_group = ibm_resource_group.resource_group.id
}

# Reserve IP addresses in advance

resource "ibm_is_subnet_reserved_ip" "db_primary" {
  provider    = ibm.secondary_region

  name        = "${var.prefix}-dr-db-primary"
  auto_delete = false
  address     = ibm_is_instance.db_primary.primary_network_attachment[0].primary_ip[0].address
  subnet      = module.vpc_region2.tier2_subnets[0].id
}

resource "ibm_is_subnet_reserved_ip" "db_standby" {
  provider    = ibm.secondary_region

  name        = "${var.prefix}-dr-db-standby"
  auto_delete = false
  address     = ibm_is_instance.db_standby.primary_network_attachment[0].primary_ip[0].address
  subnet      = module.vpc_region2.tier2_subnets[1].id
}

