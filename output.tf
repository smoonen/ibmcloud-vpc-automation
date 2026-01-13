# Output the primary and secondary LB hostnames

output region1_lb_hostname {
  value = module.vpc_region1.lb.hostname
}

output region2_lb_hostname {
  value = module.vpc_region2.lb.hostname
}

