# Architecture

## Repository boundary

This repository owns the cloud resource layer:

```text
Cloud account / subscription / project
└── openworkflow-k8s-setup
    ├── network and managed Kubernetes cluster
    ├── managed PostgreSQL server(s), database(s), and credential secrets
    ├── optional object-storage buckets
    └── cloud IAM and Kubernetes workload-identity federation

Kubernetes cluster
└── separate platform/application-deployment repositories
    ├── platform services such as ingress, certificates, identity, and Kafka
    └── OpenWorkflow Kafka Streams and actor-engine workloads
```

The infrastructure layer returns connection information and cloud-secret references. It does not create Kubernetes namespaces, service accounts, secrets, controllers, or workloads. This keeps cloud-resource lifecycle independent from cluster add-ons and applications.

## Common contract

All three stacks provide a common `deployment_handoff` output and equivalent individual outputs:

- cluster name, location, endpoint, network, subnet, and workload-identity issuer;
- database host, port, name, TLS mode, administrator username/secret reference, runtime username/secret reference, and role-provisioning requirement;
- object-storage name, cloud resource ID, and URI;
- workload cloud principal, Kubernetes namespace/service-account coordinates, and required service-account annotation;
- `kubeconfig_command`.

Database, bucket, and workload maps use stable logical keys such as `kafka_streams`, `actor_engine`, `backups`, `runtime`, and `migrations`. Downstream deployment automation selects values by logical key without relying on generated cloud resource names.

## Database identity model

There are two distinct credentials for every logical database:

1. The **migration administrator** is an actual managed-database login. It is used only by controlled schema migration and runtime-role provisioning.
2. The **runtime role** is the intended least-privilege application login. Its username and password secret are prepared by this stack, but the role must be created and granted application-specific privileges by the database-migration deployment.

This split is necessary because RDS and Azure PostgreSQL create only an administrator through their infrastructure APIs. Treating that administrator as the application identity would give every runtime excessive privileges. GCP follows the same contract even though its control plane can create additional Cloud SQL users.

The migration deployment must finish runtime-role provisioning before any application receives its runtime credential. Runtime workloads are never granted administrator-secret access.

## Provider differences

GCP supports multiple databases on one Cloud SQL instance. AWS RDS and Azure PostgreSQL Flexible Server expose one initial database per server, so their stacks create one server per configured logical database. The cloud stacks avoid SQL provisioners and network-dependent local execution.

Clusters include cloud-native networking, multi-zone managed node pools, explicit administrator identities, and provider workload identity. `workload_identities` accepts the namespace and service-account names selected by deployment configuration and creates only the corresponding cloud identity, federation relationship, and narrowly declared storage/secret permissions.

| Concern | GCP | AWS | Azure |
| --- | --- | --- | --- |
| Kubernetes administration | Explicit Google IAM members | Explicit EKS access entries | Explicit Microsoft Entra administrator groups |
| Database availability | Regional Cloud SQL | Multi-AZ RDS | Zone-redundant Flexible Server |
| Database secrets | Secret Manager | RDS-managed administrator secret and Secrets Manager runtime secret | One restricted Key Vault per database credential |
| Object-storage network path | Private Google access | S3 VPC gateway endpoint | Blob private endpoint |
| Workload federation | GKE Workload Identity | EKS IRSA | AKS Workload Identity |
