# WordPress + RDS on AWS with Terraform

This project deploys a **two-tier WordPress application** on AWS using Terraform:

- **EC2** in a public subnet running Apache + PHP + WordPress  
- **RDS MySQL** in private subnets (no public access)  
- **VPC** with one public subnet (web) and two private subnets (database)  
- **Security Groups** that only allow the web server to talk to the database

---

## Architecture

- **VPC**: `10.0.0.0/16`
- **Public subnet**: `10.0.1.0/24` – EC2/WordPress lives here, has a public IP
- **Private subnets**: `10.0.2.0/24` and `10.0.3.0/24` – RDS lives here
- **Internet Gateway + Route Table**: gives the public subnet internet access
- **EC2 Security Group (`wp-ec2-sg`)**
  - Inbound: HTTP (80) from `0.0.0.0/0`
  - Inbound: SSH (22) from `0.0.0.0/0` (lab only – should be restricted in prod)
  - Outbound: all traffic
- **RDS Security Group (`wp-rds-sg`)**
  - Inbound: MySQL (3306) **only from the EC2 security group**
  - Outbound: all traffic

WordPress connects to RDS using:

- DB name: `wordpressdb`
- DB user: `wpadmin`
- DB password: `ChangeMeStrong123!` (lab only, not for production)

These values are wired into `wp-config.php` automatically via EC2 user data.

---

## Prerequisites

- AWS account with permissions to create:
  - VPC, subnets, IGW, route tables
  - EC2 instances
  - RDS MySQL
  - Security groups
- Terraform installed (v1.3+ recommended)
- An existing **EC2 key pair** in the same region (e.g. `wp-key`)
- AWS credentials configured locally (`aws configure`, env vars, or profile)

---

## How to Deploy

Clone the repo and go into the project folder:

```bash
git clone https://github.com/tawanmaurice/rdsproject.git
cd rdsproject
