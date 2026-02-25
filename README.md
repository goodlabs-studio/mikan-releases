# Mikan Releases

Deployment guide for Mikan. Choose the deployment method that fits your environment.

## Deployment Options

| Method | Description | Guide |
| ------ | ----------- | ----- |
| **Docker Compose** | Deploy on a single server using Docker Compose | [docker/](docker/) |
| **Kubernetes** | Deploy on a Kubernetes cluster using Helm Chart (EKS, GKE, AKS, k3s, etc.) | [kubernetes/](kubernetes/) |

## Prerequisites

### Confluent Cloud API Credentials

Mikan requires Confluent Cloud API credentials for Kafka management. Follow the steps below to create them.

**1. Create a Service Account**

1. Go to [Confluent Cloud](https://confluent.cloud)
2. Navigate to **Administration > Accounts and access**
3. Go to the **Service accounts** tab and click **Add service account**
4. Enter a name (e.g., `mikan`) and description, then click **Next**

**2. Assign Permissions**

Click **Add role assignment** for each of the following:

| Scope | Role |
| ----- | ---- |
| Organization | BillingAdmin |
| Each cluster | CloudClusterAdmin |

After adding all role assignments, click **Review and create**. Verify that the access summary looks like:

```
BillingAdmin        -> Your Organization
CloudClusterAdmin   -> cluster-1 (lkc-xxxxx)
CloudClusterAdmin   -> cluster-2 (lkc-xxxxx)
```

Then click **Create**.

**3. Create an API Key**

1. Navigate to **Administration > API keys**
2. Click **Add API key** and select the service account created above
3. Set the scope to **Cloud resource management**
4. Copy the generated **Key** and **Secret**

These values will be used as `CONFLUENT_MANAGEMENT_API_KEY` and `CONFLUENT_MANAGEMENT_API_SECRET` during installation.
