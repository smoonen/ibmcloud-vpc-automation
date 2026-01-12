# IBM Cloud VPC automation
These sample Terraform modules are intended to demonstrate the automation of:

1. A simple two-tier network architecture in IBM Cloud VPC;
2. The creation of a skeleton of this architecture in a second VPC region;
3. The replication of data to this second region for disaster recovery (DR) purposes, and
4. The failover of the application to the second region.

This project is heavily inspired by: https://github.com/IBM/ibm-vpc-demo/. My thanks to [IBM Bob](https://www.ibm.com/products/bob) for helping me to speedrun aspects of this configuration including the PostgreSQL replication configuration.

## Orientation

- `failover/` - standalone module intended to activate application and database in recovery region if primary region is lost
- `templates/` - this folder holds template boot scripts for the application and database VMs
- `vpc_skeleton/` - a module used to create identical network configurations (VPC, address prefixes, subnets, load balancer) in two different regions
- `terraform.tf` - provider specification
- `variables.tf` - variable input specification
- `globals.tf` - create global resources such as resource group and DNS
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

## Failover

The failover Terraform module is a standalone module; this enables it to operate even if the primary region is unreachable by Terraform. You will need to perform a `terraform init` independently for this module. It uses the same variables as the main module, and in fact you caan link your `terraform.tfvars` file between the two modules if you wish.

The Terraform provider for IBM Cloud DNS does not allow you to modify existing resource records. Therefore you will need to import these three resources. The `query_dns.sh` script helps you to do this using the IBM Cloud CLI if you are already logged in. For example:

```bash
$ ibmcloud login --sso
$ ibmcloud plugin install cloud-dns-services
$ ./query_dns.sh
Run the following import commands after initializing your terraform workspace:
  terraform import ibm_dns_resource_record.app f6080ce1-8f60-483a-9e66-98c434099e63/59ad71f8-158d-4d10-a138-d351e5272713/CNAME:f3fc4e2f-7018-4148-9c8a-60a8feed9981
  terraform import ibm_dns_resource_record.db_primary f6080ce1-8f60-483a-9e66-98c434099e63/59ad71f8-158d-4d10-a138-d351e5272713/A:5bce7855-d712-4f45-a55b-2bef47daab88
  terraform import ibm_dns_resource_record.db_standby f6080ce1-8f60-483a-9e66-98c434099e63/59ad71f8-158d-4d10-a138-d351e5272713/A:2d08adc5-8f54-43ff-aacf-92680e0c112f
```

After this you can apply the Terraform, and the DNS records will be successfully updated together with the failover deployment.

## Notes

Individual storage snapshots are not managed by Terraform. As a result, you will be unable to successfully complete a `terraform destroy` until snapshots age out or unless you delete them; the resource group must remain in existence as long as there are snapshots in the group.

Likely you would not use first-boot scripts to fully setup your systems, but would instead manage this using an image build pipeline, and/or and orchestration solution such as Ansible Tower.

This is just a sample exercise of the replication and re-creation of resources in IBM Cloud VPC. See [this discussion on the VPC object model](https://fullvalence.com/2025/12/03/from-vmware-to-ibm-cloud-vpc-vsi-part-5-vpc-object-model/) for some considerations.

The use of Terraform, instance groups, and instance templates for stateless machines is simple and relatively low-risk. If you want to use Terraform for more stateful resources like database systems, you'll need to be careful to ensure that changes to your configuration do not cause the re-deployment of these systems as a side effect. For such cases you might use Terraform only to deploy the database, but not to manage it. It's possible to build sophisticated pipelines where you use Terraform to deploy successive versions of an application, reconfigure a load balancer, and destroy the previous version. This would require you to juggle multiple distinct Terraform workspaces, including one for your load balancer and possibly your databases, and one for each version of your application.

The snapshotting and copying of block storage volumes is [not write-order consistent](https://fullvalence.com/2025/12/03/from-vmware-to-ibm-cloud-vpc-vsi-part-6-disaster-recovery/). As a result, your replicated applications might be out of synch with your database (if, for example, the applications retain a transaction log); and your primary and standby databases may also be out of synch with one another (you should compare them to determine which may have the most up-to-date transactions, and establish that as the new primary).

