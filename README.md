# OpenWorkflow Kubernetes infrastructure

OpenTofu stacks for the cloud infrastructure shared by the OpenWorkflow Kafka Streams and actor-engine implementations.

## Scope

This repository creates only:

- a production-oriented managed Kubernetes cluster and its network;
- durable cloud IAM administrators and workload identities;
- managed PostgreSQL capacity and initial databases;
- migration-administrator and runtime credential secrets;
- explicitly configured private object-storage buckets or containers.

It deliberately does **not** install namespaces, CRDs, operators, Helm releases, Istio, cert-manager, Keycloak, Kafka, Kubernetes application secrets, or either OpenWorkflow runtime. Those belong in a separate platform/application-deployment layer.

## Clouds

| Cloud | Kubernetes | PostgreSQL | Object storage |
| --- | --- | --- | --- |
| GCP | GKE | Cloud SQL | GCS |
| AWS | EKS | RDS | S3 |
| Azure | AKS | PostgreSQL Flexible Server | Blob containers |

The GCP stack uses one Cloud SQL instance for all declared databases. AWS and Azure create one PostgreSQL server per logical database because their control-plane APIs expose one initial database and administrator login per server.

Cloud control-plane APIs do not create a correctly restricted PostgreSQL runtime role. Each stack therefore creates the managed database and migration administrator, stores both administrator and proposed runtime credentials in the cloud secret manager, and exports `database_role_provisioning_required = true`. The downstream database-migration deployment uses those secret references to create the runtime role and grant only application privileges. This repository does not execute SQL over a private database connection.

Buckets are opt-in (`buckets = {}` by default). Workload access is opt-in through `workload_identities`; the stack creates only the cloud identity, federation trust, and declared cloud-resource permissions. The deployment layer remains responsible for creating the matching Kubernetes namespace and service account.

## Usage

Prerequisites are OpenTofu 1.8+, the selected cloud CLI, cloud credentials, and `kubectl`.

```bash
cp terraform/gcp/terraform.example.tfvars terraform/gcp/terraform.tfvars
make CLOUD=gcp infra-init
make CLOUD=gcp infra-plan
make CLOUD=gcp infra-apply
make CLOUD=gcp kubeconfig
```

Replace `gcp` with `aws` or `azure` for the other stacks. Replace every documentation placeholder, especially administrator identities and operator CIDRs, before planning. These modules create billable resources.

Each stack exports provider-specific outputs plus a common sensitive `deployment_handoff` object containing cluster, database, object-storage, secret-reference, and workload-identity metadata. Secret values are not exposed as outputs. Generated GCP and Azure passwords and runtime-role passwords still exist in OpenTofu state, so production state must use an encrypted remote backend with tightly restricted access. AWS database-administrator passwords are generated and managed directly by RDS.

See [architecture](docs/architecture.md) for the boundary and [operations](docs/operations.md) for validation and lifecycle guidance.
