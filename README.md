# Mockoon ECS + ALB Deployment with Terraform

This Terraform project deploys a **Mockoon containerized API** on **AWS ECS Fargate**, exposed via an **Application Load Balancer (ALB)**. Tasks are placed in private subnets for security, and the ALB handles internet traffic and health checks.

---

## Table of Contents

- [Introduction](#introduction)  
- [Architecture Overview](#architecture-overview)  
- [Requirements](#requirements)  
- [Terraform Components](#terraform-components)  
- [Health Checks](#health-checks)  
- [Security Considerations](#security-considerations)  

---

## Architecture Overview

This is a private **ECS Fargate + ALB + ECR** setup that allows you to:

- Serve HTTP traffic publicly (via an Application Load Balancer)
- Run containers privately (in Fargate, without public IPs)
- Pull images securely from a private ECR repository
- Avoid NAT gateways using VPC Endpoints for ECR and S3 access.

---

### 🧱 1. Core Network Foundation (VPC and Subnets)

#### VPC

- Defines your main network — 10.0.0.0/16 (vpc-037244a318e080899).
- DNS support enabled so private VPC endpoints and ECS service discovery can work.
- Everything — subnets, ALB, ECS, endpoints — lives inside this VPC.

#### Subnets

- **Public subnets**: accessible from internet (for ALB)
- **Private subnets**: isolated — no direct Internet, only internal communication

| Type       | CIDR         | AZ         | Used for       | Public IP? |
| ---------- | ------------ | ---------- | -------------- | ---------- |
| `public`   | 10.0.1.0/24  | eu-west-2a | ALB            | ✅ yes      |
| `public2`  | 10.0.2.0/24  | eu-west-2b | ALB (HA)       | ✅ yes      |
| `private`  | 10.0.10.0/24 | eu-west-2a | ECS tasks      | ❌ no       |
| `private2` | 10.0.11.0/24 | eu-west-2b | ECS tasks (HA) | ❌ no       |

---

### 🌐 2. Routing and Gateways

#### Internet Gateway

- Gives your VPC outbound Internet access.
- Required so your ALB (public) can serve users on the internet.

#### Route Tables

- **Public route table**: Routes all outbound traffic (0.0.0.0/0) to the Internet Gateway.
- **Private route table**: No default internet route — stays internal. It’s connected later to VPC endpoints for private AWS API access.

---

### 🔒 3. Security Groups (Firewalls)

#### ALB Security Group

- Allows inbound HTTP (port 80) from anywhere.
- Allows outbound to anywhere (so it can reach ECS tasks).

#### ECS Task Security Group

- Inbound: allows traffic only from ALB SG, on your app port (3000).
- Outbound: allows all — ECS tasks can reach AWS APIs via endpoints.

#### VPC Endpoint Security Group

- Allows inbound 443 from ECS SG (so ECS can talk to endpoints).
- Allows outbound anywhere — needed for AWS-managed communication.

---

### ⚖️ 4. Application Load Balancer (ALB)

#### ALB

- Deployed across both public subnets.
- Internet-facing (internal = false).

#### Target Group

- ALB forwards traffic to this group.
- Uses IP target type, since Fargate tasks have no fixed EC2 host.
- Health checks `/api/health`.

#### Listener

- Listens on port 80 (HTTP).
- Forwards all requests to your target group.

#### 🧭 Flow:

- User makes a request to ALB DNS name (e.g., mockoon-alb-...amazonaws.com).
- ALB receives traffic on port 80.
- ALB routes it to the ECS service (target group) on port 3000.

---

### 🧩 5. ECS Fargate Setup

#### ECS Cluster

- Logical grouping for ECS services (no capacity management needed for Fargate).

#### IAM Role for ECS Tasks

- Allows ECS to:
  - Pull images from ECR.
  - Write logs to CloudWatch.
- Uses managed policy: AmazonECSTaskExecutionRolePolicy.

#### ECS Task Definition

- Describes the container that runs in Fargate:
  - Uses image from private ECR.
  - Defines CPU, memory, ports.
  - Runs with awsvpc mode (each task gets its own ENI & IP).
  - Port 3000 is exposed.

#### ECS Service

- Deploys and maintains the running tasks.
- Connects to ALB target group.
- Runs tasks in private subnets with no public IPs.
- Uses ECS SG to control inbound connections (only from ALB).

--- 

### 🔌 6. VPC Endpoints (Private AWS Access)

Since your ECS tasks do not have Internet access (no NAT Gateway), they can’t pull images from ECR or access S3 directly over the public Internet.

So we add VPC Endpoints:

| Endpoint  | Type      | Service                         | Purpose                      |
| --------- | --------- | ------------------------------- | ---------------------------- |
| `ecr_api` | Interface | com.amazonaws.eu-west-2.ecr.api | ECS auth & metadata          |
| `ecr_dkr` | Interface | com.amazonaws.eu-west-2.ecr.dkr | Pull Docker layers           |
| `s3`      | Gateway   | com.amazonaws.eu-west-2.s3      | Underlying ECR layer storage |

These allow ECS tasks in private subnets to reach ECR and S3 securely inside the AWS network, without public Internet.

---

### 🧠 7. Deployment Order (Terraform Flow)

1. VPC + Subnets created
2. Route Tables + IGW + Associations added
3. Security Groups created
4. VPC Endpoints deployed
5. ALB + Target Group + Listener created
6. ECS Cluster, IAM Role, Task Definition created
7. ECS Service started (tasks run inside private subnets)

---

### ⚙️ 8. Runtime Request Flow (Step-by-Step)

Here’s how traffic flows when everything is running:

1. 🧑‍💻 User opens browser → hits ALB DNS name
→ http://mockoon-alb-xxxxx.eu-west-2.elb.amazonaws.com/api/health
2. 🌍 ALB (public subnet) receives HTTP request on port 80.
3. 🧭 ALB checks its target group for healthy ECS tasks.
4. 🚦 ALB forwards request (HTTP) to ECS task private IP (in private subnet) on port 3000.
5. 🧱 ECS Task (Fargate) receives the request and processes it (e.g., Mockoon mock API).
6. 📨 ECS Task sends response (HTTP 200 OK) back to ALB.
7. 🌐 ALB returns the response to the user over the Internet.
8. 🧾 Logs from the container are automatically pushed to CloudWatch Logs using the ECS execution role.

---

### 🛡️ 9. Key Security & Design Advantages

| Component              | Purpose                                                      |
| ---------------------- | ------------------------------------------------------------ |
| **Private Subnets**    | Keeps ECS containers off the public Internet.                |
| **ALB Security Group** | Exposes only HTTP port 80 publicly.                          |
| **ECS SG**             | Only allows inbound from ALB.                                |
| **VPC Endpoints**      | Enables private ECR/S3 access — no NAT needed.               |
| **IAM Roles**          | Fine-grained permissions for ECS execution.                  |
| **Health Checks**      | Keeps only healthy containers in the load balancer rotation. |

---

### 🧭 10. Summary Visualization (Simplified Flow)

```
User (HTTP:80)
   │
   ▼
[Application Load Balancer - Public Subnets]
   │
   ▼
[Target Group] --> [ECS Fargate Tasks - Private Subnets :3000]
   │                       │
   │                       ├─> [ECR API & DKR Endpoints]──> [Private ECR]
   │                       └─> [S3 Gateway Endpoint]───────> [S3 Buckets]
   │
   ▼
CloudWatch Logs (async)
```
