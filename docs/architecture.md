# Architecture

## Repository boundary

This repository owns the cloud resource layer:

```text
Cloud account / subscription / project
└── openworkflow-k8s-setup
    ├── network and managed Kubernetes cluster
    ├── managed PostgreSQL server(s), database(s), and login(s)
    └── optional object-storage buckets

Kubernetes cluster
└── separate bootstrap/deployment repositories
    ├── platform services such as ingress, certificates, identity, and Kafka
    └── OpenWorkflow Kafka Streams and actor-engine workloads
```

The infrastructure layer returns connection information; it does not consume that information by writing Kubernetes secrets or installing workloads. This keeps cloud-resource lifecycle independent from cluster add-ons and applications.

## Common contract

All three stacks provide equivalent outputs:

- `cluster_name` and `cluster_location`;
- `database_hosts`, `database_port`, `database_names`, `database_usernames`, and sensitive `database_passwords`;
- `bucket_names`;
- `kubeconfig_command`.

Database and bucket maps use stable logical keys such as `kafka_streams`, `actor_engine`, and `backups`. Downstream deployment automation can select values by logical key without relying on generated cloud resource names.

## Provider differences

GCP supports multiple databases and users on one Cloud SQL instance through its control-plane API. AWS RDS and Azure PostgreSQL Flexible Server expose one initial database and administrative login per server. Their stacks therefore create one server per configured logical database, avoiding SQL provisioners, bootstrap pods, or network-dependent local execution.

Clusters include cloud-native networking, managed node pools, and the provider's workload-identity capability. Workload identities and object-storage permissions are not created here because they require application service-account and namespace choices owned by deployment configuration.
