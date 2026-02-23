# Mikan Deployment Guide

This document describes how to deploy the Mikan application using Docker Compose.

## Quick Start

### Option A: One-Command Installation (Recommended)

Run the following command to automatically download, configure, and start Mikan:

```bash
curl -o- https://raw.githubusercontent.com/goodlabs-studio/mikan-releases/main/docker/install.sh | bash
```

The script will:

1. Check prerequisites (Docker, Docker Compose)
2. Download and extract the distribution package
3. Prompt for required configuration (Confluent API keys, ECR token)
4. Generate encryption key automatically
5. Start all services

**Requirements before running:**

- Docker and Docker Compose installed
- ECR token (provided by Mikan team)
- Confluent Cloud API credentials

---

### Option B: Manual Installation

#### 1. Download Distribution Package

**Available Downloads:**

- Latest: `https://mikan-public.s3.amazonaws.com/distribution/latest.zip` (Not available yet)
- Staging: `https://mikan-public.s3.amazonaws.com/distribution/staging.zip`
- Specific version: `https://mikan-public.s3.amazonaws.com/distribution/mikan-{version}.zip` (Not available yet)

```bash
# Download and extract
curl -O https://mikan-public.s3.amazonaws.com/distribution/staging.zip
unzip staging.zip
cd mikan-distribution
```

#### 2. Configure Environment Variables

```bash
# Copy example file and edit
cp .env.example .env
vi .env  # Edit required variables (see table below)
```

**Required Variables:**

| Variable                          | Description                       | Required |
| --------------------------------- | --------------------------------- | -------- |
| `ENCRYPTION_KEY`                  | 32-character encryption key       | Yes      |
| `CONFLUENT_MANAGEMENT_API_KEY`    | Confluent Cloud API key           | Yes      |
| `CONFLUENT_MANAGEMENT_API_SECRET` | Confluent Cloud API secret        | Yes      |
| `POSTGRES_PASSWORD`               | Database password                 | No       |
| `IMAGE_TAG`                       | Docker image tag (staging/latest) | No       |

- **ENCRYPTION_KEY**: A 32-character random string to encrypt API credentials in database
- **CONFLUENT_MANAGEMENT_API_KEY/SECRET**: Create a service account in Confluent Cloud with EnvironmentAdmin and BillingAdmin permissions

#### 3. Start Services

```bash
# Login to ECR (required for pulling private images)
# Replace <YOUR_ECR_TOKEN> with the token from generate-ecr-token.sh
docker login --username AWS --password-stdin 624622221797.dkr.ecr.us-east-1.amazonaws.com <<< <YOUR_ECR_TOKEN>

# Pull images and start all services
docker compose pull
docker compose up -d
```

---

## Table of Contents

### Getting Started

- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Running Services](#running-services)
- [Access the Application](#access-the-application)

### Operations & Maintenance

- [Service Management](#service-management)
- [Updating Images](#updating-images)
- [Version Management](#version-management)
- [Cron Configuration](#cron-configuration)
- [Troubleshooting](#troubleshooting)

---

# Getting Started

## Prerequisites

- Docker Engine 20.10+
- Docker Compose V2 (recommended) or V1
- ECR Authorization Token (provided by Mikan team)

```bash
# Check Docker version
docker --version
docker compose version
```

### ECR Authorization Token

The ECR authorization token is required to pull private Docker images from Mikan's container registry.

- **How to obtain:** Contact the Mikan team to receive your ECR authorization token
- **Token validity:** 12 hours from generation
- **Usage:** Use the token to login to Docker before pulling images (see examples below)

**Note:** If your token expires (after 12 hours), you will need to request a new token from the Mikan team and login again before pulling images.

---

## Initial Setup

### Environment Variables Reference

See [Quick Start](#quick-start) section above for required variables. Additional optional variables:

| Variable               | Description                        | Default                 |
| ---------------------- | ---------------------------------- | ----------------------- |
| `PORT`                 | API server port                    | `3333`                  |
| `DATABASE_SSL`         | Enable database SSL                | `false`                 |
| `CORS_ALLOWED_ORIGINS` | Allowed CORS origins               | `http://localhost:3000` |
| `COLLECTION_INTERVAL`  | Cron collection interval (seconds) | `3600`                  |
| `API_ENDPOINT`         | Cron API endpoint                  | `http://api:3333`       |

### Obtaining Confluent Cloud Credentials

To get `CONFLUENT_MANAGEMENT_API_KEY` and `CONFLUENT_MANAGEMENT_API_SECRET`:

1. Create a service account in Confluent Cloud with:
   - EnvironmentAdmin permission for each environment resource you want to access
   - BillingAdmin permission for the organization
   - CloudClusterAdmin permission for each cluster you want to collect chargeback data from
2. Generate an API key and secret for this service account with Cloud resource management scope
3. Use the generated key and secret as `CONFLUENT_MANAGEMENT_API_KEY` and `CONFLUENT_MANAGEMENT_API_SECRET`
4. For each cluster, generate an API key with Kafka cluster resource scope. Save these credentials and register them in the Mikan app's API Keys page

### Obtaining MongoDB Atlas API Credentials

To collect billing data from MongoDB Atlas, you need to create API credentials for each organization.

#### Step 1: Get Organization ID

1. Go to [cloud.mongodb.com](https://cloud.mongodb.com)
2. Select your organization from the organization selector
3. The Organization ID is in the URL after `/org/`:
   ```
   https://cloud.mongodb.com/v2#/org/67c9cffa530932749e175023/projects
                                    └─────────────────────────┘
                                         Organization ID
   ```

#### Step 2: Create Service Account

1. After selecting the organization, navigate to **Access Manager** > **Applications**
2. Click **Create Service Account**
3. Enter a name for the service account (e.g., `mikan-billing`)
4. Add the **Organization Billing Viewer**, **Organization Member** permission
5. Click **Create**

#### Step 3: Generate API Credentials

1. After creating the service account, you'll see the **Client ID** and **Client Secret**
2. **Important:** Copy the Client Secret immediately - it won't be shown again
3. Register these credentials in the Mikan app:
   - Go to **MongoDB** > **Organizations** page
   - Add your organization with the Client ID and Client Secret

**Note:** Repeat these steps for each MongoDB Atlas organization you want to collect billing data from.

## Running Services

See [Quick Start](#quick-start) for initial setup. After configuration:

```bash
# Run all services (including cron)
docker compose up -d

# Run without cron
docker compose up -d database api app
```

### Services Overview

| Service    | Container Name | Port | Description              |
| ---------- | -------------- | ---- | ------------------------ |
| `database` | mikan-database | 5432 | PostgreSQL database      |
| `api`      | mikan-api      | 3333 | Backend API server       |
| `app`      | mikan-app      | 3000 | Frontend web application |
| `cron`     | mikan-cron     | -    | Scheduled task runner    |

---

## Access the Application

After starting the services:

1. Open your browser and go to `http://localhost:3000`
2. Login with default admin credentials:
   - **Email:** `admin@mikan.local`
   - **Password:** `Admin123!`
3. You will be prompted to change the password on first login

---

# Operations & Maintenance

## Service Management

### Check Service Status

```bash
# All services status
docker compose ps
```

### Stop Services

```bash
# Stop all services (keep containers)
docker compose stop

# Stop all services and remove containers
docker compose down

# Stop specific service
docker compose stop api
docker compose stop cron
```

### Restart Services

```bash
# Restart all
docker compose restart

# Restart specific service
docker compose restart api
docker compose restart app
```

### View Logs

```bash
# All services logs
docker compose logs -f

# Specific service logs
docker compose logs -f api
docker compose logs -f cron

# Last 100 lines only
docker compose logs --tail=100 api
```

---

## Updating Images

### Method 1: Manual Update

```bash
# 1. Stop services
docker compose down

# 2. Login to ECR
# Replace <YOUR_ECR_TOKEN> with the token from generate-ecr-token.sh
docker login --username AWS --password-stdin 624622221797.dkr.ecr.us-east-1.amazonaws.com <<< <YOUR_ECR_TOKEN>

# 3. Pull latest images
docker compose pull

# 4. Start services
docker compose up -d
```

### Method 2: Update Specific Service Only

```bash
# Update API service only
docker compose pull api
docker compose up -d api

# Update frontend only
docker compose pull app
docker compose up -d app
```

---

## Version Management

### Change Image Tag

Modify `IMAGE_TAG` value in `.env` file:

```bash
# Latest version (default)
IMAGE_TAG=latest

# Staging version
IMAGE_TAG=staging

# Specific version
IMAGE_TAG=1.2.3
```

### Apply Version Change

```bash
# After modifying .env file
docker compose down
docker compose pull
docker compose up -d
```

### Rollback

```bash
# 1. Change to previous version in .env
vi .env
# IMAGE_TAG=1.1.0

# 2. Restart services
docker compose down
docker compose pull
docker compose up -d
```

### Check Current Image Version

```bash
# Check images of running containers
docker compose images

# Check specific container's image info
docker inspect mikan-api --format='{{.Config.Image}}'
```

---

## Cron Configuration

Consumer offset collection cron jobs can be run in two ways.

### Option 1: Run as Docker Container (Recommended)

Use the `cron` service included in Docker Compose.

```bash
# Run all services including cron
docker compose up -d

# Check cron logs
docker compose logs -f cron
```

**Advantages:**

- No additional setup required
- Isolated execution in container environment
- Integrated management with Docker Compose
- Automatic restart support

**Configuration:**

You can modify cron-related settings in the `.env` file:

```bash
# Collection interval (in seconds, default: 3600 = 1 hour)
COLLECTION_INTERVAL=3600

# API endpoint (use service name within Docker)
API_ENDPOINT=http://api:3333
```

### Option 2: Run Script Directly (For Standalone Environments)

For running directly on the host without Docker.

```bash
# Navigate to mikan-cron directory
cd ../mikan-cron

# Configure environment variables
cp .env.example .env
vi .env  # Edit required variables

# Run in background (continues after terminal closes)
nohup env $(cat .env | grep -v '^#' | grep -v '^$' | xargs) ./startup.sh > offset-collector.log 2>&1 &

# Check if running
ps aux | grep startup.sh

# View logs
tail -f offset-collector.log

# Stop the collector
pkill -f startup.sh
```

**Disable Cron Service (Exclude from Docker):**

To run Docker Compose but exclude cron:

```bash
# Run without cron
docker compose up -d database api app

# Or stop cron service only
docker compose stop cron
```

### Cron Options Comparison

| Item                   | Docker Container              | Run Script Directly          |
| ---------------------- | ----------------------------- | ---------------------------- |
| Setup Complexity       | Low                           | High                         |
| Kafka CLI Installation | Included in container         | Manual installation required |
| Resource Management    | Managed by Docker             | Manual management            |
| Log Management         | `docker compose logs`         | File/stdout                  |
| Restart Policy         | Automatic (`restart: always`) | Manual/systemd               |
| Use Case               | Docker environments           | Bare metal/VM                |

---

## Troubleshooting

### Container Won't Start

```bash
# Check detailed logs
docker compose logs --tail=50 <service-name>

# Check container status
docker compose ps -a
```

### Database Connection Failure

```bash
# Check database status
docker exec mikan-database pg_isready -U postgres

# Check database logs
docker compose logs database
```

### Port Conflict

```bash
# Check ports in use
lsof -i :3333
lsof -i :3000
lsof -i :5432

# Change port in .env
PORT=3334
```

### Reset Data

```bash
# Warning: All data will be deleted!
docker compose down -v
docker compose up -d
```

---

## Useful Commands

```bash
# Start all
docker compose up -d

# Stop all
docker compose down

# Check status
docker compose ps

# View logs
docker compose logs -f

# Update images
docker compose pull && docker compose up -d

# Restart specific service
docker compose restart <service-name>

# Access container shell
docker exec -it mikan-api sh
docker exec -it mikan-database psql -U postgres -d mikan

# Check resource usage
docker stats
```
