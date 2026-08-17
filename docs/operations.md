# Operations

## State and secrets

Configure a remote OpenTofu backend in `terraform/gcp/backend.tf` (kept
environment-specific) before the first shared deployment. The generated
database and Keycloak passwords are sensitive but are stored in state so that
Cloud SQL users and Secret Manager versions stay consistent. Limit state access
to platform operators and enable object versioning and retention.

Never commit `terraform.tfvars`, generated Helmfile values, kubeconfigs, plans,
or state. The repository ignore rules cover their standard locations.

## DNS and certificates

After `make infra-apply`, read the `gateway_ip` output and create records for:

- `auth.<root-domain>`
- each OpenWorkflow tenant/API hostname

Point them at the reserved address. Bootstrap first with Let's Encrypt staging.
Inspect `Certificate/platform-tls` and only then switch `acme_server` to
`https://acme-v02.api.letsencrypt.org/directory`.

## Upgrades

Upgrade one layer at a time: Gateway API CRDs, cert-manager, Istio base/control
plane, External Secrets, monitoring, Strimzi, Kafka, Keycloak, and finally
OpenWorkflow runtimes. Run `make bootstrap-diff`, read upstream upgrade notes,
take database backups, and validate both engines between stateful upgrades.

The versions live in `bootstrap/environments/base.yaml`; provider versions live
in `terraform/gcp/versions.tf`.

## Recovery

Cloud SQL backups and point-in-time recovery are enabled by default. A complete
recovery test also needs export/restore procedures for Keycloak, Kafka topics,
and application databases. Strimzi PVCs are not a backup; add a provider object
storage backup design before treating the platform as production-ready.
