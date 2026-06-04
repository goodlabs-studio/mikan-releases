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

### MongoDB Atlas API Credentials (optional)

Skip this section if you do not run MongoDB Atlas. Atlas integration is **disabled by default** in fresh deploys and has to be enabled explicitly.

Mikan reads Atlas resources and billing using **per-organization OAuth2 service-account credentials**. Each Atlas organization you want Mikan to see needs its own Service Account and gets registered separately in the Mikan UI — there is no single global Atlas key.

**1. Create an Atlas Service Account (per organization)**

For each MongoDB Atlas organization:

1. Go to [cloud.mongodb.com](https://cloud.mongodb.com) and select the organization.
2. Copy the Organization ID from the URL — it's the segment after `/org/`:
   ```
   https://cloud.mongodb.com/v2#/org/67c9cffa530932749e175023/projects
                                    └─────────── Organization ID ──┘
   ```
3. Navigate to **Access Manager > Applications**.
4. Click **Create Service Account**, name it (e.g. `mikan`), and grant these org-level roles (Mikan only reads):
   - **Organization Member** — list orgs, projects, clusters, processes, and metrics
   - **Organization Billing Viewer** — read invoices for chargeback
5. After creation, **copy the Client Secret immediately** — Atlas does not show it again. The Client ID stays visible.

**2. Register the credentials in Mikan**

After Mikan is installed and you've logged in:

1. Open **MongoDB > Organizations** in the sidebar.
2. Add an entry with the **Organization ID**, **Client ID**, and **Client Secret** from step 1.
3. Repeat for each Atlas organization.

Mikan encrypts the Client ID / Client Secret with the deployment's `ENCRYPTION_KEY` before storing them — the same caveat as Confluent applies: losing the encryption key makes the stored credentials unrecoverable.

**3. Enable the Atlas integration**

The Atlas feature is gated by a system setting (`mongodb_atlas.enabled`) that ships as `false`. Until you flip it, the MongoDB sidebar entries stay hidden and Atlas sync jobs are skipped. Two ways to enable it:

- **During install:** the installer asks whether to enable Atlas, and writes the setting on your behalf when you say yes.
- **Later, via the API:** log in, grab a session token, and POST the GraphQL mutation below:
  ```bash
  curl -sf http://localhost:3333/graphql \
    -X POST \
    -H "Authorization: Bearer <SESSION_TOKEN>" \
    -H "Content-Type: application/json" \
    -d '{"query":"mutation { updateSystemSetting(key:\"mongodb_atlas.enabled\", value:\"true\") { key value } }"}'
  ```
  Refresh the UI after toggling.

To disable later, run the same mutation with `value:"false"`.

### Azure Databricks Credentials (optional)

Skip this section if you do not run Databricks on Azure. The integration is **disabled by default** and requires Unity Catalog — there is no fallback path.

Unlike the Confluent and MongoDB Atlas integrations, Databricks credentials are **global**: a single Azure Service Principal is shared across every subscription and workspace Mikan reads. Workspaces themselves are discovered automatically once the SP has access — you do not register them one-by-one in Mikan.

**1. Create an Azure AD Service Principal**

1. In the Azure portal, go to **Microsoft Entra ID > App registrations > New registration**.
2. Name it (e.g. `mikan-databricks`) and register.
3. Open the new app's **Certificates & secrets** page and create a **New client secret**. Copy the value immediately — it is shown only once.
4. From the app's **Overview** page, copy the **Application (client) ID** and the **Directory (tenant) ID**.

You'll use these as the `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, and `AZURE_TENANT_ID` environment variables below.

**2. Assign Azure subscription roles**

For every subscription that contains Databricks workspaces Mikan should see, grant the Service Principal both of these roles (Subscription scope):

| Role | Purpose |
| ---- | ------- |
| `Reader` | List subscriptions, resource groups, and Databricks workspaces |
| `Cost Management Reader` | Query `Microsoft.CostManagement` for per-resource Azure costs |

These are read-only. Mikan never writes to Azure.

**3. Enable Unity Catalog and grant system schema access (required)**

Mikan derives Databricks chargeback from **Unity Catalog system tables** — there is no alternative. Every workspace you want included needs:

- A **Unity Catalog metastore** attached.
- The metastore's `system.billing` schema **enabled** (system schemas are off by default). Enable from the Databricks account console under **Account > Settings > Manage account**, or via the Account API:
  ```bash
  curl -X PUT \
    -H "Authorization: Bearer <ACCOUNT_ADMIN_TOKEN>" \
    "https://accounts.azuredatabricks.net/api/2.0/accounts/<ACCOUNT_ID>/metastores/<METASTORE_ID>/systemschemas/billing"
  ```
  Repeat for any other system schema Mikan adds in the future.
- The Service Principal added to the workspace and granted permissions:
  1. **Workspace level** (Workspace admin → **Settings > Identity and access > Service principals > Add**): add the SP and grant the **User** entitlement so it can call workspace APIs.
  2. **SQL warehouse** (a warehouse Mikan can use to execute the billing query): grant the SP **Can use** on a serverless or pro warehouse. Mikan auto-selects one per workspace but you can pin a specific warehouse from the Mikan UI later.
  3. **Unity Catalog grants** (run in any UC-enabled SQL editor as a metastore admin):
     ```sql
     GRANT USE CATALOG ON CATALOG system            TO `<SP application id>`;
     GRANT USE SCHEMA  ON SCHEMA  system.billing    TO `<SP application id>`;
     GRANT SELECT      ON TABLE   system.billing.usage       TO `<SP application id>`;
     GRANT SELECT      ON TABLE   system.billing.list_prices TO `<SP application id>`;
     ```
     Use the SP's Application (client) ID as the principal — Databricks resolves it automatically.

Without all of the above, the workspace billing sync fails with `INSUFFICIENT_PERMISSIONS` on `system.billing.usage`.

**4. Set the credentials in `.env`**

```
AZURE_TENANT_ID=<tenant id>
AZURE_CLIENT_ID=<application/client id>
AZURE_CLIENT_SECRET=<client secret>
```

The installer also prompts for these and writes them into the generated `.env`.

**5. Enable the Databricks integration**

The Databricks feature ships disabled (system_setting `databricks.enabled = 'false'`). Until you turn it on, the Databricks sidebar entries stay hidden and Databricks sync jobs are skipped.

- **During install:** the installer asks whether to enable Databricks, and writes the setting when you say yes.
- **Later, via the API:** same GraphQL `updateSystemSetting` mutation as MongoDB Atlas, with `key: "databricks.enabled"`.

Once enabled and credentials are present, Mikan discovers subscriptions on its next scheduled run, syncs workspaces, and starts loading billing usage from Unity Catalog.

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
| `cloud.mongodb.com` | MongoDB Atlas OAuth token endpoint and Atlas Admin API (`/api/atlas/v2/*`) — only if the Atlas integration is enabled |
| `login.microsoftonline.com` | Azure AD OAuth token endpoint — only if the Azure Databricks integration is enabled |
| `management.azure.com` | Azure Resource Manager + Cost Management — only if Azure Databricks is enabled |
| `*.azuredatabricks.net` | Per-workspace Databricks REST API (SQL warehouses, statements, Unity Catalog) — only if Azure Databricks is enabled |

Add wildcard rules for `*.confluent.cloud` if your firewall does not allow per-subdomain entries.

### Post-Install Security Hardening

A few things to take care of right after the first successful deploy:

- **Default admin password is one-time only.** Logging in with `admin@mikan.local` / `Admin123!` immediately prompts you to set a new password before any other action is allowed. The default credentials become invalid after this change.
- **`ENCRYPTION_KEY` is permanent.** This value encrypts every Confluent cluster API key, Schema Registry API key, and other secrets stored in the database. **Do not change or lose it** — if the value is rotated or the deployment is recreated without the original key, the encrypted credentials cannot be decrypted and every key/secret must be re-entered through the UI. Back the value up to a secret manager (Vault, AWS Secrets Manager, 1Password, etc.) as soon as install completes.
- **`.env` contains plaintext secrets.** Restrict file permissions (`chmod 600 .env`) and exclude the file from any host-level backups that aren't themselves encrypted.
