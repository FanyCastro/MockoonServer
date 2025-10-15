# =====================================================
# Terraform Infrastructure for ECS + ALB + ECR (Private)
# =====================================================
# This configuration sets up:
# - A VPC with public & private subnets
# - Application Load Balancer (public)
# - ECS Fargate service (private)
# - IAM roles for ECS execution
# - VPC Endpoints for private ECR & S3 access (no NAT required)
# =====================================================


# -----------------------------
# VPC & Networking
# -----------------------------

# Main Virtual Private Cloud (VPC)
# Defines the main network range for all resources
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true # required for endpoint private DNS resolution
  enable_dns_hostnames = true # required for endpoint private DNS resolution
}

# -----------------------------
# Public Subnets (for ALB)
# -----------------------------

# Public Subnet in Availability Zone A
# ALB and other internet-facing components live here
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true # Ensures instances launched here get public IPs
}

# Public Subnet in Availability Zone B (High Availability)
resource "aws_subnet" "public2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true
}

# -----------------------------
# Private Subnets (for ECS Tasks)
# -----------------------------
# ECS tasks will run in private subnets for better security
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "eu-west-2a"
}

resource "aws_subnet" "private2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "eu-west-2b"
}

# -----------------------------
# Internet Gateway & Routes
# -----------------------------
# Required for public subnets (for ALB internet access)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Route Table for public subnets
# Allows outbound internet access via Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0" # Route all traffic to the internet
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Associate public route table with both public subnets
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_assoc2" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public.id
}

# -----------------------------
# Private Route Table for private subnets
# -----------------------------
# private route table is where we'll attach the S3 gateway endpoint routes
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
}

# Associate private route table with private subnets
resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_assoc2" {
  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_route_table.private.id
}

# -----------------------------
# Security Groups
# -----------------------------

# ECS Task Security Group
# Allows traffic ONLY from the ALB on the container port
resource "aws_security_group" "ecs_sg" {
  name   = "${var.project_name}-sg"
  vpc_id = aws_vpc.main.id

  # Inbound: allow traffic from ALB only (ALB -> container_port)
  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # Restrict to ALB SG
  }

  # Outbound: allow all (ECS tasks need to initiate connections, e.g., to endpoints)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB Security Group
# Allows inbound HTTP (port 80) from the internet
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow HTTP inbound to ALB"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow from anywhere
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group for Interface VPC Endpoints (ECR endpoints)
# This SG allows inbound HTTPS (443) from ECS tasks, and outbound to anywhere.
# We keep endpoint SG separate from ecs_sg to avoid odd circular rules and be explicit.
resource "aws_security_group" "vpce_sg" {
  name        = "${var.project_name}-vpce-sg"
  description = "SG for interface VPC endpoints (allow ECS tasks to reach endpoints)"
  vpc_id      = aws_vpc.main.id

  # Allow ECS tasks (using ecs_sg) to connect to endpoints on 443
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  # Allow endpoint ENIs to perform outbound as needed (e.g., to AWS service)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------
# Application Load Balancer (ALB)
# -----------------------------
resource "aws_lb" "mockoon_alb" {
  name               = "${var.project_name}-alb"
  internal           = false # Internet-facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public2.id]
}

# Target Group for ECS Tasks
# ALB forwards requests to this target group (ECS tasks)
resource "aws_lb_target_group" "mockoon_tg" {
  name        = "${var.project_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip" # Fargate uses IP target type
  vpc_id      = aws_vpc.main.id

  # Health check to ensure tasks are healthy
  health_check {
    path                = "/api/health"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    matcher             = "200-399"
  }
}

# ALB Listener (port 80)
# Routes incoming HTTP requests to the target group
resource "aws_lb_listener" "mockoon_listener" {
  load_balancer_arn = aws_lb.mockoon_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mockoon_tg.arn
  }
}

# -----------------------------
# ECS Cluster, Task Definition, and Service
# -----------------------------

# ECS Cluster to host our Fargate tasks
resource "aws_ecs_cluster" "cluster" {
  name = "${var.project_name}-cluster"
}

# IAM Role for ECS Task Execution
# Allows ECS to pull images from ECR and write logs to CloudWatch
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "mockoon-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# Attach AWS-managed ECS execution policy to the role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition (Fargate)
# Defines container image, resources, and networking
resource "aws_ecs_task_definition" "mockoon_task" {
  family                   = "${var.project_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-container"
      image     = aws_ecr_repository.mockoon.repository_url
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# ECS Service (Fargate)
# Runs and manages the ECS tasks, connected to the ALB
resource "aws_ecs_service" "mockoon_service" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.mockoon_task.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Network configuration - Private subnets only (no public IPs)
  network_configuration {
    subnets          = [aws_subnet.private.id, aws_subnet.private2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  # Attach service to ALB target group
  load_balancer {
    target_group_arn = aws_lb_target_group.mockoon_tg.arn
    container_name   = "${var.project_name}-container"
    container_port   = var.container_port
  }

  # Ensure these dependencies exist before service creation
  depends_on = [
    aws_ecs_task_definition.mockoon_task,
    aws_lb_listener.mockoon_listener
  ]
}


# -----------------------------
# VPC Endpoints (Private ECR & S3 Access)
# -----------------------------
# These endpoints allow ECS tasks in private subnets to:
# - Pull container images from ECR (via API + Docker endpoints)
# - Access image layers stored in S3
# No need for NAT Gateway or internet access.

# ECR API Endpoint (for auth & metadata)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.eu-west-2.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id, aws_subnet.private2.id]
  security_group_ids  = [aws_security_group.vpce_sg.id] # use endpoint SG
  private_dns_enabled = true
}

# ECR Docker Registry Endpoint (for image layer pulls)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.eu-west-2.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id, aws_subnet.private2.id]
  security_group_ids  = [aws_security_group.vpce_sg.id] # use endpoint SG
  private_dns_enabled = true
}

# S3 Gateway Endpoint (used by ECR under the hood)
# Attach to both public and private route tables so private subnets can reach S3
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.eu-west-2.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id, aws_route_table.private.id]
}
