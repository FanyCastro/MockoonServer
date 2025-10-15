# Mockoon ECS + ALB Deployment with Terraform

This Terraform project deploys a **Mockoon containerized API** on **AWS ECS Fargate**, exposed via an **Application Load Balancer (ALB)**. Tasks are placed in private subnets for security, and the ALB handles internet traffic and health checks.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)  
- [Requirements](#requirements)  
- [Terraform Components](#terraform-components)  
- [Health Checks](#health-checks)  
- [Security Considerations](#security-considerations)  

---

## Architecture Overview

Client → Internet → ALB (in public subnet)

ECS tasks respond → ALB → Client

Security groups enforce this:
- ALB SG: allows 0.0.0.0/0 → port 80
- ECS SG: allows traffic only from ALB SG → container port

Key points:

- **ALB**: Public subnets, internet-facing, handles health checks.  
- **ECS Tasks**: Private subnets, no public IP (`assign_public_ip = false`).  
- **Security Groups**: ECS tasks only allow traffic from ALB; ALB allows HTTP from anywhere.  
- **Target Group Health Checks**: Verify ECS task endpoints are healthy.  

---

## Requirements

- Terraform >= 1.5.0  
- AWS CLI configured with proper credentials  
- An AWS account with permissions to manage:
  - VPC, Subnets, Security Groups  
  - ECS, ECR, ALB, IAM Roles  

---

## Terraform Components

### 1. VPC & Networking

- **VPC**: 10.0.0.0/16  
- **Public Subnets**: For ALB (10.0.1.0/24 & 10.0.2.0/24)  
- **Private Subnets**: For ECS tasks (10.0.10.0/24 & 10.0.11.0/24)  
- **Internet Gateway**: For ALB internet access  
- **Route Tables**: Public route table for ALB  

### 2. Security Groups

- **ALB SG**: Allow HTTP (port 80) from 0.0.0.0/0  
- **ECS SG**: Allow container port traffic only from ALB SG  

### 3. ECR Repository

- Stores the **Mockoon Docker image**  
- Terraform creates it automatically if not existing  

### 4. ECS Cluster

- Fargate cluster for running tasks  
- Tasks use `awsvpc` networking  

### 5. ECS Task Definition

- Defines the **Mockoon container**:
  - CPU & Memory configuration  
  - Container port mapping (default: `3000`)  
  - Execution IAM role for ECS tasks to access ECR  

### 6. ECS Service

- Launches tasks in **private subnets**  
- Connects tasks to **ALB target group**  
- Health checks configured to `/api/health` endpoint  

### 7. ALB & Target Group

- Internet-facing ALB in **public subnets**  
- Target group uses **IP-based targets** (tasks in private subnets)  
- Health check endpoint: `/api/health`  

---

## Health Checks

- ALB target group performs HTTP health checks on /api/health.
- Settings:
    - Interval: 30s
    - Timeout: 5s
    - Healthy Threshold: 2
    - Unhealthy Threshold: 2

If the health check endpoint does not return 200, the target will stay unhealthy.

---

## Security Considerations

- ECS tasks in private subnets for enhanced security
- ECS security group restricts access to only the ALB
- ALB is public-facing, but only handles HTTP traffic
- Optional: use NAT Gateway if ECS tasks need outbound internet access (for ECR or updates)