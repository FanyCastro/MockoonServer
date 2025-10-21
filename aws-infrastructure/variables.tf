variable "aws_region" {
  description = "AWS region"
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Project name prefix"
  default     = "mockoon"
}

variable "container_port" {
  description = "Port Mockoon exposes"
  default     = 3000
}

variable "cpu" {
  description = "Task CPU (Fargate)"
  default     = 256
}

variable "memory" {
  description = "Task memory (Fargate)"
  default     = 512
}

variable "desired_count" {
  description = "Number of Fargate tasks"
  default     = 1
}
