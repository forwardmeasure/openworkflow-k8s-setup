# Operations

## Prepare

Choose one cloud and copy its example variables file:

```bash
cp terraform/aws/terraform.example.tfvars terraform/aws/terraform.tfvars
```

Replace the documentation-only operator CIDR with the public CIDR used by administrators or CI. Keep real `terraform.tfvars`, plans, and state out of Git.

Configure an encrypted remote state backend before a shared or production deployment. Generated GCP/Azure passwords and generated runtime-role passwords are stored in state even though their values are exposed only through cloud secret managers.

Supply durable administrator identities rather than a personal account:

- GCP: `cluster_administrator_members` contains Google IAM group or service-account members.
- AWS: `cluster_administrator_principal_arns` contains IAM role ARNs used in EKS access entries.
- Azure: `aks_admin_group_object_ids` contains Microsoft Entra group object IDs.

Every public Kubernetes API endpoint is restricted to the declared operator/CI CIDRs. Database endpoints are private. Azure Blob uses a private endpoint, AWS uses an S3 VPC gateway endpoint, and GKE nodes use Private Google Access.

## Validate and deploy

```bash
make fmt
make validate-all
make test-all
make CLOUD=aws infra-init
make CLOUD=aws infra-plan
make CLOUD=aws infra-apply
make CLOUD=aws outputs
make CLOUD=aws kubeconfig
```

The plan is saved inside the selected cloud directory. `infra-apply` applies that reviewed plan rather than producing a new one.

## Hand-off to deployment automation

Read the common handoff object without writing it to a repository:

```bash
tofu -chdir=terraform/aws output -json deployment_handoff
```

The output is marked sensitive because it includes the cluster endpoint and credential-secret references, although it contains no secret values. The platform/application-deployment layer is responsible for:

- creating namespaces and Kubernetes service accounts;
- installing cluster-wide controllers and platform services;
- applying the service-account annotations exported by `workload_identity_bindings`;
- resolving cloud-secret references into the migration/runtime configuration without copying values into Git;
- deploying either OpenWorkflow implementation.

## Database role provisioning

Do not deploy an application using `database_administrator_usernames`. The database-migration deployment must:

1. run under a workload identity that declares both `administrator_database_keys` and `runtime_database_keys` for the target database;
2. retrieve the administrator and runtime password values from their cloud-secret references;
3. connect over the private database endpoint using the exported TLS mode and provider CA trust;
4. create or rotate the declared runtime role as `LOGIN`, `NOSUPERUSER`, `NOCREATEDB`, `NOCREATEROLE`, and without schema ownership;
5. apply schema migrations as the migration administrator;
6. grant the runtime role only the database, schema, table, sequence, and routine privileges required by that application;
7. configure default privileges for objects created by later migrations;
8. verify the runtime role cannot create roles/databases or access another logical database.

Only after this succeeds may the runtime deployment resolve its `runtime_database_keys` secret. The infrastructure output deliberately reports `database_role_provisioning_required = true` on every cloud.

## Workload identity handoff

The example configuration creates separate `runtime` and `migrations` cloud identities. The cloud stack does not create their Kubernetes service accounts. The deployment repository must create the exact namespace/service-account pair from the output and apply the provider annotation:

- GCP: `iam.gke.io/gcp-service-account`;
- AWS: `eks.amazonaws.com/role-arn`;
- Azure: `azure.workload.identity/client-id` and the Azure workload identity pod label required by the deployment chart.

Do not grant administrator database secrets to the runtime identity.

## Destruction

Production-oriented HA and deletion protection are enabled by default. Before an intentional destroy:

1. confirm backups and retention requirements;
2. set deletion protection off and apply that change separately;
3. on AWS, keep `skip_final_snapshot = false` unless the environment is explicitly disposable;
4. inspect object retention policies and bucket contents—object-storage `force_destroy` remains false unless explicitly enabled;
5. retain or transfer the cloud credential secrets required to restore the databases.

Azure Key Vault purge protection cannot be disabled after creation; deleted credential vaults remain recoverable for their retention period.
