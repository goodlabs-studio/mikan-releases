# Mikan Helm Chart - Kubernetes Deployment Guide

Deploy Mikan on any Kubernetes cluster (EKS, GKE, AKS, k3s, minikube, etc.).

## Prerequisites

- Kubernetes cluster with `kubectl` access configured
- Helm 3.x installed

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

If no `.env` file exists, the installer will interactively prompt you for:
- Database connection details (host, port, username, password, etc.)
- Confluent Cloud API credentials
- Encryption key (auto-generated if `openssl` is available)

The answers are saved to `.env` for future use.

### 2. Choose namespace and access method

The installer will ask you to:
- **Namespace** - Kubernetes namespace to deploy into (default: `mikan`)
- **Access method** - Ingress or port-forward

### 3. Review and run the generated command

The installer prints a `helm upgrade --install` command with all your configuration values. Review it, then copy and run.

You can also specify a custom env file path:

```bash
./install.sh /path/to/my.env
```

### 4. Verify

```bash
kubectl get pods -n mikan

kubectl wait --for=condition=Ready pod -l app.kubernetes.io/part-of=mikan -n mikan --timeout=120s
```

### 5. Default login credentials

After the first deployment, log in with:

- **Email:** `admin@mikan.local`
- **Password:** `SuperAdmin123!`

> **Warning:** Please change the password after first login.

## Configuration

### Global

| Parameter              | Description                | Default                    |
| ---------------------- | -------------------------- | -------------------------- |
| `fullnameOverride`     | Override release name      | (release name)             |
| `global.imageTag`      | Container image tag        | `latest`                   |

### Database

| Parameter           | Description                          | Default    |
| ------------------- | ------------------------------------ | ---------- |
| `database.external` | Use an external database (e.g., RDS) | `false`    |
| `database.host`     | External database host               | `""`       |
| `database.port`     | Database port                        | `5432`     |
| `database.username` | Database username                    | `postgres` |
| `database.password` | Database password                    | `postgres` |
| `database.name`     | Database name                        | `mikan`    |
| `database.ssl`      | Enable SSL connection                | `false`    |

### API

| Parameter                      | Description                         | Default      |
| ------------------------------ | ----------------------------------- | ------------ |
| `api.replicas`                 | Number of API replicas              | `1`          |
| `api.port`                     | API service port                    | `3333`       |
| `api.confluent.apiKey`         | Confluent Cloud API key             | `""`         |
| `api.confluent.apiSecret`      | Confluent Cloud API secret          | `""`         |
| `api.encryptionKey`            | Encryption key for database secrets | `""`         |
| `api.env.NODE_ENV`             | Node environment                    | `production` |
| `api.env.CORS_ALLOWED_ORIGINS` | Allowed CORS origins                | `""`         |

### App (Frontend)

| Parameter              | Description                        | Default |
| ---------------------- | ---------------------------------- | ------- |
| `app.replicas`         | Number of app replicas             | `1`     |
| `app.port`             | App service port                   | `3000`  |
| `app.env.VITE_API_URL` | API URL that the frontend will use | `""`    |

### Cron

| Parameter                      | Description                    | Default |
| ------------------------------ | ------------------------------ | ------- |
| `cron.enabled`                 | Enable cron service            | `true`  |
| `cron.env.COLLECTION_INTERVAL` | Collection interval in seconds | `3600`  |

### Ingress

| Parameter             | Description         | Default |
| --------------------- | ------------------- | ------- |
| `ingress.enabled`     | Enable ingress      | `false` |
| `ingress.className`   | Ingress class name  | `alb`   |
| `ingress.host`        | Ingress hostname    | `""`    |
| `ingress.annotations` | Ingress annotations | `{}`    |
| `ingress.tls`         | TLS configuration   | `[]`    |

## Operations

### Upgrade

```bash
helm upgrade mikan oci://public.ecr.aws/q0l2x1j9/mikan-chart-staging -n mikan
```

### Rollback

```bash
helm rollback mikan -n mikan
```

### Uninstall

```bash
helm uninstall mikan -n mikan
```

> **Warning:** This does NOT delete PVCs (database data). To fully clean up:
>
> ```bash
> kubectl delete pvc -l app.kubernetes.io/part-of=mikan -n mikan
> ```

### Port forwarding (no Ingress)

If you don't have an Ingress configured, you can access the services via `kubectl port-forward`:

```bash
# Terminal 1: API
kubectl port-forward svc/mikan-api 3333:3333 -n mikan

# Terminal 2: App
kubectl port-forward svc/mikan-app 3000:3000 -n mikan
```

Then open `http://localhost:3000` in your browser.

> **Note:** Make sure `VITE_API_URL` is set to `http://localhost:3333/graphql` when using port-forward.

### View logs

```bash
kubectl logs -l app.kubernetes.io/component=api -n mikan -f
kubectl logs -l app.kubernetes.io/component=app -n mikan -f
kubectl logs -l app.kubernetes.io/component=cron -n mikan -f
```
