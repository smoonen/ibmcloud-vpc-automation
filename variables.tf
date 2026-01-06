variable "ibmcloud_api_key" {
  description = "Enter your IBM Cloud API Key"
}

variable "region" {
  type        = string
  default     = "us-south"
  description = "Name of the IBM Cloud region where the resources need to be provisioned.(Examples: us-east, us-south, etc.) For more information, see [Region and data center locations for resource deployment](https://cloud.ibm.com/docs/overview?topic=overview-locations)."
}

variable "prefix" {
  type        = string
  default     = "example"
  description = "Prefix to use for resource names"
}

variable "network" {
  type        = string
  default     = "192.168.200.0/24"
  description = "Subnet in CIDR form that will be assigned to the VPC and split between 2 application tiers and 3 zones."
}

variable "ssh_authorized_key" {
  type = string
  description = "Public SSH key to be installed on VSI for default user."
}

variable "allowed_ips" {
  type        = set(string)
  default     = ["0.0.0.0/0"]
  description = "Allowed inbound IPs and CIDRs to public load balancer"
}

variable "ecdsa_private_key" {
  type = string
  description = "Private ECDSA host key for tier 1 servers"
}

variable "ecdsa_public_key" {
  type = string
  description = "Public ECDSA host key for tier 1 servers"
}

variable "ed25519_private_key" {
  type = string
  description = "Private ED25519 host key for tier 1 servers"
}

variable "ed25519_public_key" {
  type = string
  description = "Public ED25519 host key for tier 1 servers"
}

variable "rsa_private_key" {
  type = string
  description = "Private RSA host key for tier 1 servers"
}

variable "rsa_public_key" {
  type = string
  description = "Public RSA host key for tier 1 servers"
}

