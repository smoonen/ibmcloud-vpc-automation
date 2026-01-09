# IBM Cloud VPC automation
These sample Terraform modules are intended to demonstrate the automation of:

1. A simple two-tier network architecture in IBM Cloud VPC;
2. The creation of a skeleton of this architecture in a second VPC region;
3. The replication of data to this second region for disaster recovery (DR) purposes, and
4. The failover of the application to the second region.

This project is heavily inspired by: https://github.com/IBM/ibm-vpc-demo/. My thanks to [IBM Bob](https://www.ibm.com/products/bob) for helping me to speedrun aspects of this configuration including the PostgreSQL replication configuration.

## Orientation

- `templates/` - this folder holds template boot scripts for the application and database VMs
- `vpc_skeleton/` - a module used to create identical network configurations (VPC, address prefixes, subnets, load balancer) in two different regions
- `terraform.tf` - provider specification
- `variables.tf` - variable input specification
- `globals.tf` - create many global resources such as resource group and DNS
- `region1.tf` - create application and database, register in DNS
- `replicate.tf` - create policy to snapshot database and copy it to recovery region
- `region2_prep.tf` - create skeleton (VPC, addresss prefixes, subnets, load balancer, reserved IPs) in recovery region in preparation for failover

## Topology

The two-tier "application" deployed by this is extremely simple. From the outside in, the topology consists of:

- A public load balancer in front of:
- Three or more stateless "application" VSIs leveraging scalable _instance groups_, exposing SSH, and for which `psql` is installed. These are entitled to connect to:
- Two database VSIs configured with PostgreSQL in streaming replication mode. DNS is used to address the primary. (Failover is beyond the scope of this project.)

All of the VSIs are enabled for outbound public network access by means of a public gateway.

The application VSIs are configured with a common SSH host key so that they are interchangeable when reached through the load balancer. In our poor-man's architecture, this is the SSH equivalent of multiple web servers sharing the same server certificate.

After provisioning, you can to SSH to the load balancer hostname to connect to one of the application VSIs, and then run `psql -h db-primary.example.com testdb appuser` without authentication. The secondary DB server is in read-only mode and is configured to listen as well, so that you can connect to it too.

## Notes

Likely you would not use first-boot scripts to fully setup your systems, but would instead manage this using an orchestration solution such as Ansible Tower.

The use of Terraform, instance groups, and instance templates for stateless machines is simple and straightforward. If you want to use Terraform for more stateful resources like database systems, you'll need to be careful to ensure that changes to your configuration do not cause the re-deployment of these systems as a side effect. For such cases you might use Terraform only to deploy the database. It's possible to build sophisticated pipelines where you use Terraform to deploy successive versions of an application, reconfigure a load balancer, and destroy the previous version. This would require you to juggle multiple distinct Terraform configurations and state machines, including one for your load balancer and possibly your databases, and one for each version of your application.

