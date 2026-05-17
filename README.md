# CloudSentinel 🛡️

**Cloud-Native Observability & Auto-Scaling Platform**

> Built with AWS (EC2, ASG, ALB, CloudWatch) · Terraform IaC · Docker · Prometheus · Grafana · GitHub Actions CI/CD

---

## Architecture Overview

```
Internet
   │
   ▼
┌──────────────────────────────────────────────────────────┐
│                    AWS ap-south-1                         │
│                                                           │
│   ┌─────────┐     ┌───────────────────────────────────┐  │
│   │  Route53│────▶│   Application Load Balancer (ALB) │  │
│   └─────────┘     └──────────────┬────────────────────┘  │
│                          ┌───────┴──────┐                 │
│                          ▼              ▼                  │
│              ┌─────────────────────────────────────────┐  │
│              │  Auto Scaling Group (2–6 × EC2 t3.micro)│  │
│              │   ┌──────────┐      ┌──────────┐        │  │
│              │   │ App:3000 │  ... │ App:3000 │        │  │
│              │   │ Docker   │      │ Docker   │        │  │
│              │   └──────────┘      └──────────┘        │  │
│              └─────────────────────────────────────────┘  │
│                                                           │
│   ┌─────────────────────┐  ┌────────────────────────┐    │
│   │    Prometheus        │  │  Grafana :3001         │    │
│   │    :9090             │◀─│  (pre-built dashboards)│    │
│   │  + Alertmanager:9093 │  └────────────────────────┘    │
│   └─────────────────────┘                                 │
│                                                           │
│   ┌──────────────┐  ┌──────────┐  ┌──────────────────┐  │
│   │ Node Exporter│  │ cAdvisor │  │  CloudWatch Logs  │  │
│   │ :9100        │  │ :8080    │  │  + Alarms + SNS   │  │
│   └──────────────┘  └──────────┘  └──────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

---

## Stack

| Layer | Technology |
|-------|-----------|
| Cloud | AWS (EC2, ALB, ASG, S3, CloudWatch, SNS, SSM) |
| IaC | Terraform ≥ 1.7 |
| App | Node.js 20 + Express + prom-client |
| Containers | Docker (multi-stage), Docker Compose |
| Metrics | Prometheus + Node Exporter + cAdvisor |
| Dashboards | Grafana (auto-provisioned) |
| Alerting | Alertmanager + CloudWatch Alarms + SNS Email |
| LB | NGINX (local) / AWS ALB (production) |
| CI/CD | GitHub Actions (test → scan → build → plan → apply → deploy → smoke) |

---

## Quick Start (Local – Docker Compose)

### Prerequisites
- Docker ≥ 24 + Docker Compose v2
- (For AWS) AWS CLI configured, Terraform ≥ 1.7

### 1. Clone & start all services

```bash
git clone https://github.com/YOUR_USERNAME/cloudsentinel.git
cd cloudsentinel
docker compose up -d --build
```

### 2. Access the stack

| Service | URL | Credentials |
|---------|-----|------------|
| CloudSentinel App | http://localhost:3000 | – |
| NGINX LB | http://localhost:80 | – |
| Prometheus | http://localhost:9090 | – |
| Grafana | http://localhost:3001 | admin / cloudsentinel |
| Alertmanager | http://localhost:9093 | – |
| cAdvisor | http://localhost:8080 | – |
| Node Exporter | http://localhost:9100 | – |

### 3. Generate load & watch dashboards

```bash
chmod +x scripts/load-test.sh
./scripts/load-test.sh http://localhost:80 60 30
```

Open Grafana → **CloudSentinel – Observability Dashboard** to watch metrics in real time.

---

## AWS Deployment (Terraform)

### Prerequisites
- AWS credentials with sufficient IAM permissions
- An ECR repository named `cloudsentinel-app`
- S3 bucket for Terraform state (optional, update `main.tf` backend block)

### 1. Push image to ECR

```bash
aws ecr create-repository --repository-name cloudsentinel-app --region ap-south-1

aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin \
  <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com

docker build -t cloudsentinel-app docker/app/
docker tag cloudsentinel-app:latest \
  <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/cloudsentinel-app:latest
docker push <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/cloudsentinel-app:latest
```

### 2. Deploy infrastructure

```bash
cd terraform
terraform init
terraform plan -var="alert_email=your@email.com"
terraform apply
```

### 3. Confirm SNS subscription
Check your inbox for the AWS SNS confirmation email and click "Confirm subscription".

---

## CI/CD Pipeline

```
push to main
     │
     ├── Test (npm test + lint)
     ├── Security Scan (Trivy: image + Terraform)
     ├── Build & Push → ECR
     ├── Terraform Plan
     ├── Terraform Apply  ← requires GitHub Environment approval
     ├── ASG Instance Refresh (rolling deploy, 50% min healthy)
     └── Smoke Test (ALB /health × 5 retries)
```

### GitHub Secrets required

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM access key |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key |
| `SLACK_WEBHOOK_URL` | Slack alert webhook (optional) |

---

## Auto-Scaling Behaviour

| Trigger | Action |
|---------|--------|
| CPU > 70% (2 min) | Scale out – add instances |
| CPU < 30% (stable) | Scale in – remove instances |
| ALB requests > 1000/min/target | Scale out |
| Weekday 08:30 IST | Set desired = 3 |
| Weekday 20:00 IST | Return to desired = 2 |
| Max instances | 6 |

---

## Alerting

| Alert | Threshold | Severity |
|-------|-----------|----------|
| AppDown | Service unreachable 1 min | Critical |
| HighErrorRate | 5XX rate > 5% | Critical |
| HighResponseLatency | p95 > 500ms | Warning |
| HighCPUUsage | CPU > 80% (5 min) | Warning |
| HighMemoryUsage | Mem > 85% (5 min) | Warning |
| ContainerRestarting | Any restart | Critical |

---

## Project Structure

```
cloudsentinel/
├── .github/workflows/ci-cd.yml      # GitHub Actions pipeline
├── docker/
│   ├── app/
│   │   ├── Dockerfile               # Multi-stage, non-root
│   │   ├── index.js                 # Express app + Prometheus metrics
│   │   └── package.json
│   ├── alertmanager/alertmanager.yml
│   ├── grafana/provisioning/        # Auto-loaded dashboards + datasources
│   ├── nginx/nginx.conf             # Load balancer config
│   └── prometheus/
│       ├── prometheus.yml           # Scrape config
│       └── alerts.yml               # Alerting rules
├── terraform/
│   ├── main.tf                      # Provider + backend
│   ├── variables.tf
│   ├── vpc.tf                       # VPC, subnets, SGs, NAT
│   ├── alb.tf                       # ALB, target group, listener
│   ├── autoscaling.tf               # Launch template, ASG, scaling policies
│   ├── cloudwatch.tf                # Alarms, dashboard, SNS, log groups
│   └── outputs.tf
├── scripts/load-test.sh             # Apache Bench load tester
├── docker-compose.yml               # Full local stack
└── README.md
```

---

## Certifications (Author)

- Oracle Cloud Infrastructure 2025 DevOps Professional – CI/CD & Agile
- Oracle Cloud Infrastructure 2025 Generative AI Professional
- AWS Academy Data Engineering
