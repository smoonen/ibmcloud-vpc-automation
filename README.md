# IBM Cloud VPC automation
The primary purpose of this sample Terraform is to demonstrate the automation of a simple two-tier network architecture in IBM Cloud VPC.

The secondary purpose is to take that resulting architecture and demonstrate how to replicate or recreate various components of that architecture to another IBM Cloud region for disaster recovery purposes.

This project is heavily inspired by: https://github.com/IBM/ibm-vpc-demo/

## Topology

The two-tier "application" deployed by this is extremely simple. From the outside in, the topology consists of:

- A public load balancer in front of
- Three or more "application" VSIs leveraging scalable _instance groups_, exposing SSH, and for which `psql` is installed and preconnected to the database. The database connection is to
- Two "database" VSIs configured with PostgreSQL in streaming replication mode. DNS is used to address the primary. (Failover is beyond the scope of this project.)

All of the VSIs are enabled for outbound public network access by means of a public gateway.

The "application" VSIs are stateless.

