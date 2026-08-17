# OpenWorkflow Kubernetes infrastructure

OpenTofu stacks for the cloud infrastructure shared by the OpenWorkflow Kafka Streams and actor-engine implementations.

## Scope

This repository creates only:

- a managed Kubernetes cluster and its network;
- managed PostgreSQL capacity, initial databases, and login credentials;
- explicitly configured object-storage buckets or containers.

It deliberately does **not** install namespaces, CRDs, operators, Helm releases, Istio, cert-manager, Keycloak, Kafka, application secrets, or either OpenWorkflow runtime. Those belong in a separate cluster-bootstrap or application-deployment layer.

## Clouds

| Cloud | Kubernetes | PostgreSQL | Object storage |
| --- | --- | --- | --- |
| GCP | GKE | Cloud SQL | GCS |
| AWS | EKS | RDS | S3 |
| Azure | AKS | PostgreSQL Flexible Server | Blob containers |

The GCP stack uses one Cloud SQL instance with a database and login per runtime. RDS and Azure create one server per runtime because their infrastructure APIs expose only the initial database and administrator login during server creation. No SQL or Kubernetes provisioner is used.

Buckets are opt-in (`buckets = {}` by default). Neither OpenWorkflow implementation currently defines a required object-storage layout, so the repository does not invent one.

## Usage

Prerequisites are OpenTofu 1.8+, the selected cloud CLI, cloud credentials, and `kubectl`.

```bash
cp terraform/gcp/terraform.example.tfvars terraform/gcp/terraform.tfvars
make CLOUD=gcp infra-init
make CLOUD=gcp infra-plan
make CLOUD=gcp infra-apply
make CLOUD=gcp kubeconfig
```

Replace `gcp` with `aws` or `azure` for the other stacks. Review the plan carefully: these modules create billable resources and their examples disable or reduce some production safeguards.

Each stack exports cluster details, private database endpoints, database names, usernames, generated passwords, and bucket names. Passwords are sensitive OpenTofu outputs but remain in state, so use an encrypted remote state backend with tightly restricted access.

See [architecture](docs/architecture.md) for the boundary and [operations](docs/operations.md) for validation and lifecycle guidance.
