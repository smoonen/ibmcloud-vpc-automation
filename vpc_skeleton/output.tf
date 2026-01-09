output "vpc_id" {
  value = ibm_is_vpc.vpc.id
}

output "default_sg_id" {
  value = data.ibm_is_security_group.default_sg.id
}

output "tier1_subnets" {
  value = ibm_is_subnet.subnets_tier1
}

output "tier2_subnets" {
  value = ibm_is_subnet.subnets_tier2
}

output "lb" {
  value = ibm_is_lb.lb
}

output "lb_pool_id" {
  value = ibm_is_lb_pool.pool.pool_id
}

output "lb_listener" {
  value = ibm_is_lb_listener.listener
}

