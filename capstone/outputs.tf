output "alb_dns_name" {
  value = module.compute.alb_dns_name
}

output "aurora_endpoint" {
  value = module.data.aurora_endpoint
}
