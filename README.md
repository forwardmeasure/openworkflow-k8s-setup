# OpenWorkflow Kubernetes setup

This repository provisions a production-shaped Kubernetes platform on which
both OpenWorkflow implementations can be installed independently:

- `openworkflow-kafka-streams`
- `openworkflow-actor-engine`

GCP/GKE is the first provider implementation. The portable bootstrap installs
Gateway API, cert-manager, Istio, External Secrets Operator, Keycloak, Strimzi,
and (optionally) the Prometheus operator stack. AWS/EKS and Azure/AKS can add
provider stacks without duplicating the bootstrap.

## Ownership boundary

| Layer | Owner | Contents |
|---|---|---|
| Cloud infrastructure | `terraform/<provider>` | Network, cluster, managed PostgreSQL, cloud identity, secret containers, public IP |
| Cluster bootstrap | `bootstrap` | Operators, CRDs, identity provider, Kafka, TLS issuer, shared Gateway |
| Runtime | OpenWorkflow repositories | Engine charts, migrations, application policies, runtime images |

Terraform state and credentials are deliberately excluded from this repository.
Use a remote, encrypted state backend before sharing an environment.

## GCP quick start

Prerequisites: OpenTofu 1.8+, `gcloud`, `kubectl`, Helm 3.15+, Helmfile 1.x,
`jq`, and `yq` v4. Authenticate Application Default Credentials and select a
GCP project with billing enabled.

```bash
cp terraform/gcp/terraform.example.tfvars terraform/gcp/terraform.tfvars
# Edit terraform.tfvars. In particular set project_id, root_domain and
# acme_email, and decide whether deletion protection is appropriate.

make infra-init
make infra-plan
make infra-apply
make kubeconfig
make bootstrap
make verify
```

`make bootstrap` installs the pinned standard Gateway API CRDs first, exports
non-secret Terraform outputs to a generated Helmfile environment, and then
syncs the platform releases in dependency order.

The default issuer is Let's Encrypt staging. Set `acme_server` to the production
endpoint only after DNS points at `gateway_ip` and staging certificate issuance
works. Terraform does not create DNS records because authoritative DNS may be
outside the cluster project.

After bootstrap, see [workloads/README.md](workloads/README.md) for deploying
either engine. Architecture decisions and the multi-cloud seam are described in
[docs/architecture.md](docs/architecture.md).

## Useful commands

```bash
make validate             # offline Terraform validation plus chart linting
make bootstrap-diff       # show Helmfile changes
make outputs              # cloud and workload contract outputs
make verify               # cluster readiness checks
```

There is intentionally no one-command destroy target. Destroying the GKE
cluster, Cloud SQL instance, secrets, and addresses must be an explicit
operator action after backups and deletion protection have been reviewed.
