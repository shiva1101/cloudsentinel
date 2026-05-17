variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1"   # Mumbai – closest to Noida, India
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "project_name" {
  description = "Project identifier used in resource names"
  type        = string
  default     = "cloudsentinel"
}

# ── VPC ───────────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "availability_zones" {
  description = "AZs to spread resources across"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

# ── EC2 / ASG ────────────────────────────────────────────────────────────────
variable "instance_type" {
  description = "EC2 instance type for app nodes"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI for EC2 (Amazon Linux 2023 in ap-south-1)"
  type        = string
  default     = "ami-0f5ee92e2d63afc18"
}

variable "asg_min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of instances in the ASG"
  type        = number
  default     = 6
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in the ASG"
  type        = number
  default     = 2
}

# ── Scaling thresholds ────────────────────────────────────────────────────────
variable "scale_out_cpu_threshold" {
  description = "CPU % that triggers scale-out"
  type        = number
  default     = 70
}

variable "scale_in_cpu_threshold" {
  description = "CPU % that triggers scale-in"
  type        = number
  default     = 30
}

# ── CloudWatch ────────────────────────────────────────────────────────────────
variable "alert_email" {
  description = "Email for CloudWatch SNS alerts"
  type        = string
  default     = "snaniketkumar@gmail.com"
}

variable "cloudwatch_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}
