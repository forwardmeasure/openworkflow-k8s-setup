# Operations

## Prepare

Choose one cloud and copy its example variables file:

```bash
cp terraform/aws/terraform.example.tfvars terraform/aws/terraform.tfvars
```

Replace the documentation-only operator CIDR with the public CIDR used by administrators or CI. Keep real `terraform.tfvars`, plans, and state out of Git.

Configure an encrypted remote state backend before a shared or production deployment. Generated database passwords are stored in state even though their outputs are marked sensitive.

## Validate and deploy

```bash
make fmt
make validate-all
make CLOUD=aws infra-init
make CLOUD=aws infra-plan
make CLOUD=aws infra-apply
make CLOUD=aws outputs
make CLOUD=aws kubeconfig
```

The plan is saved inside the selected cloud directory. `infra-apply` applies that reviewed plan rather than producing a new one.

## Hand-off to deployment automation

Read the logical database and bucket maps from outputs. Do not commit sensitive output values. The cluster bootstrap/deployment layer is responsible for:

- creating namespaces and Kubernetes service accounts;
- installing cluster-wide controllers and platform services;
- granting workload identities access to cloud resources;
- placing connection values in its chosen secret-management system;
- deploying either OpenWorkflow implementation.

## Destruction

Production-oriented deletion protection is enabled by default where the provider exposes it. Example files may disable it for disposable environments. Inspect database snapshots, object retention policies, and bucket contents before destroying a stack; object-storage `force_destroy` remains false unless explicitly enabled.
