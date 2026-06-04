# Mikan Releases

Deployment guide for Mikan. Choose the deployment method that fits your environment.

## Deployment Options

| Method | Description | Guide |
| ------ | ----------- | ----- |
| **Docker Compose** | Deploy on a single server using Docker Compose | [docker/](docker/) |
| **Kubernetes** | Deploy on a Kubernetes cluster using Helm Chart (EKS, GKE, AKS, k3s, etc.) | [kubernetes/](kubernetes/) |

## Prerequisites

### Confluent Cloud API Credentials

Mikan reads Kafka resources, metrics, and billing from Confluent Cloud — it never writes. A single shared service account with read-only role bindings is sufficient.

**1. Create a Service Account**

1. Go to [Confluent Cloud](https://confluent.cloud)
2. Navigate to **Administration > Accounts and access**
3. Go to the **Service accounts** tab and click **Add service account**
4. Enter a name (e.g., `mikan`) and description, then click **Next**

**2. Assign Permissions**

Click **Add role assignment** for each row below. These are the minimum roles Mikan needs end-to-end:

| Scope | Role | Purpose |
| ----- | ---- | ------- |
| Organization | `BillingAdmin` | Read invoice / cost line items |
| Organization | `MetricsViewer` | Read per-topic / per-cluster usage metrics from the Telemetry API |
| Each environment | `Operator` | List topics, ACLs, consumer groups, and other cluster metadata for every cluster in the environment (no data-plane access) |
| Each environment's Schema Registry cluster | `DataDiscoveryRead` | Read Business Metadata / Tags from Stream Catalog for topic auto-mapping (optional — skip if you do not plan to use auto-mapping) |

Notes:

- `Operator` is granted at the **environment** scope, not per cluster — it cascades to every cluster underneath, including clusters created later.
- `CloudClusterAdmin` is wider than what Mikan needs and should not be used. `EnvironmentAdmin` is also unnecessary.
- The Schema Registry role binding is only needed if you want Mikan to auto-map topics to Business Applications / Cost Centers from Confluent Catalog. Environments without it will simply skip the auto-mapping step.

After adding all role assignments, click **Review and create**, then **Create**.

**3. Create the Cloud (organization) API Key**

This key drives Mikan's calls to `api.confluent.cloud` and the Telemetry API.

1. Navigate to **Administration > API keys**
2. Click **Add API key** and select the service account created above
3. Set the scope to **Cloud resource management**
4. Copy the generated **Key** and **Secret**

These values are used as `CONFLUENT_MANAGEMENT_API_KEY` and `CONFLUENT_MANAGEMENT_API_SECRET` during installation.

**4. Create a Kafka Cluster API Key per cluster**

Mikan also needs one Kafka REST API key per cluster (used for topic / ACL / consumer-group listings):

1. From the same **API keys** page, add a key per cluster, selecting the same `mikan` service account as the owner
2. Set the scope to **Kafka cluster** for the target cluster
3. After installation, register each key/secret in the Mikan UI at **API Keys**

**5. Create a Schema Registry API Key per environment (optional — for auto-mapping)**

Required only if you assigned `DataDiscoveryRead` above and want topic auto-mapping.

1. From the **API keys** page, add a key per environment, selecting the same `mikan` service account
2. Set the scope to **Schema Registry** for that environment's SR cluster
3. After installation, register each key/secret in the Mikan UI at **Schema Registry API Keys**

Environments without a registered Schema Registry key simply skip Catalog lookups during topic sync — no errors.

### ECR Access Token

Mikan's container images live in a private AWS ECR registry. The installer prompts for an ECR token that authenticates `docker pull`. The token is **short-lived (~12 hours)** — AWS expires it automatically. Request a fresh token from the Mikan team (`mikan@goodlabs.studio`) whenever you:

- Run a first-time install
- Pull updated images (`docker compose pull` after `IMAGE_TAG` bump)
- Re-deploy on a different host

Old tokens stop working silently — if `docker pull` fails with an authentication error, request a new token.

### Network / Firewall Allowlist

Mikan makes outbound HTTPS calls to several Confluent endpoints. If the host runs behind a firewall or HTTP proxy, the following domains must be reachable from the Mikan API and cron containers:

| Endpoint | Purpose |
| -------- | ------- |
| `api.confluent.cloud` | Cloud management API — environments, clusters, service accounts, API keys, billing |
| `api.telemetry.confluent.cloud` | Telemetry API — per-topic usage metrics |
| `pkc-*.<region>.<cloud>.confluent.cloud` | Per-cluster Kafka REST endpoints — topics, ACLs, consumer groups (exact subdomain varies per cluster) |
| `psrc-*.<region>.<cloud>.confluent.cloud` | Per-environment Schema Registry endpoints — Catalog reads (only if auto-mapping is enabled) |

Add wildcard rules for `*.confluent.cloud` if your firewall does not allow per-subdomain entries.

### Post-Install Security Hardening

A few things to take care of right after the first successful deploy:

- **Default admin password is one-time only.** Logging in with `admin@mikan.local` / `Admin123!` immediately prompts you to set a new password before any other action is allowed. The default credentials become invalid after this change.
- **`ENCRYPTION_KEY` is permanent.** This value encrypts every Confluent cluster API key, Schema Registry API key, and other secrets stored in the database. **Do not change or lose it** — if the value is rotated or the deployment is recreated without the original key, the encrypted credentials cannot be decrypted and every key/secret must be re-entered through the UI. Back the value up to a secret manager (Vault, AWS Secrets Manager, 1Password, etc.) as soon as install completes.
- **`.env` contains plaintext secrets.** Restrict file permissions (`chmod 600 .env`) and exclude the file from any host-level backups that aren't themselves encrypted.
