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

# Create an account settings resource so that we can leverage a side effect:
# The ID of this resource is the same as our account ID
resource "ibm_iam_account_settings" "settings" {
}

