# Mikan Helm Chart - Kubernetes Deployment Guide

Deploy Mikan on any Kubernetes cluster (EKS, GKE, AKS, k3s, minikube, etc.).

> **Note:** Ingress is currently only supported on AWS EKS (ALB). For other clusters, use port-forwarding to access the services.

## Prerequisites

- Kubernetes cluster with `kubectl` access configured
- Helm 3.x installed
- ECR Token (provided by the Mikan team, contact mikan@goodlabs.studio)
- [Confluent Cloud API credentials](../README.md#confluent-cloud-api-credentials)
- AWS Load Balancer Controller installed on the cluster (required for Ingress on EKS)

## Quick Start

```bash
mkdir mikan-installer && cd mikan-installer
curl -LO https://raw.githubusercontent.com/goodlabs-studio/mikan-releases/main/kubernetes/install.sh
chmod +x install.sh
./install.sh
```

## Installation

### 1. Run the installer

```bash
./install.sh
```

The installer will guide you through the entire setup:

1. **ECR Login** - Enter the ECR Token provided by the Mikan team
2. **Environment config** - If no `.env` file exists, interactively prompts for:
   - Database connection details (host, port, username, password, etc.)
   - Confluent Cloud API credentials
   - Encryption key (auto-generated if `openssl` is available)
   - Ingress settings
3. **Deployment environment** - Choose Staging or Production
4. **Namespace** - Kubernetes namespace to deploy into (default: `mikan-staging` or `mikan-production`)
5. **Helm command** - Prints a ready-to-run `helm upgrade --install` command with all configuration values

You can also specify a custom env file path:

```bash
./install.sh /path/to/my.env
```

### 2. Verify

```bash
kubectl get pods -n mikan-staging

kubectl wait --for=condition=Ready pod -l app.kubernetes.io/part-of=mikan -n mikan-staging --timeout=120s
```

### 3. Default login credentials

After the first deployment, log in with:

- **Email:** `admin@mikan.local`
- **Password:** `SuperAdmin123!`

> **Warning:** Please change the password after first login.

## Operations

### Upgrade

To upgrade Mikan, re-run the installer. It will use the existing `.env` file and generate a new `helm upgrade --install` command with the latest chart:

```bash
./install.sh
```

### Rollback

```bash
helm rollback mikan -n mikan-staging
```

### Uninstall

```bash
helm uninstall mikan -n mikan-staging
```

### Ingress (ALB)

The installer configures AWS ALB Ingress when you enable Ingress during setup. You can modify the following values in your `.env` file after installation:

| Parameter             | Description                                        | Default           |
| --------------------- | -------------------------------------------------- | ----------------- |
| `INGRESS_ENABLED`     | Enable Ingress                                     | `true`            |
| `INGRESS_SCHEME`      | `internet-facing` (public) or `internal` (private) | `internet-facing` |
| `INGRESS_HOST`        | Domain name (e.g., `mikan.example.com`)            | `""`              |
| `ACM_CERTIFICATE_ARN` | ACM certificate ARN for HTTPS                      | `""`              |

Re-run `./install.sh` after making changes.

To check the ALB address:

```bash
kubectl get ingress -n mikan-staging
```

### Port forwarding (no Ingress)

If you don't have an Ingress configured, you can access the services via `kubectl port-forward`:

```bash
# Terminal 1: API
kubectl port-forward svc/mikan-api 3333:3333 -n mikan-staging

# Terminal 2: App
kubectl port-forward svc/mikan-app 3000:3000 -n mikan-staging
```

Then open `http://localhost:3000` in your browser.

> **Note:** Make sure `VITE_API_URL` is set to `http://localhost:3333/graphql` when using port-forward.

### View logs

```bash
kubectl logs -l app.kubernetes.io/component=api -n mikan-staging -f
kubectl logs -l app.kubernetes.io/component=app -n mikan-staging -f
kubectl logs -l app.kubernetes.io/component=cron -n mikan-staging -f
```
