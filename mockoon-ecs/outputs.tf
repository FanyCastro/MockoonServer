output "repository_url" {
  value = data.aws_ecr_repository.mockoon.repository_url
}

output "ecs_service_name" {
  value = aws_ecs_service.mockoon_service.name
}

output "public_ip" {
  value = aws_subnet.public.id
}

output "mockoon_alb_dns" {
  value = aws_lb.mockoon_alb.dns_name
}
