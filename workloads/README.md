# Deploying OpenWorkflow runtimes

The platform bootstrap creates shared infrastructure and the actor-engine
database Secret. It does not deploy either runtime or guess application image
digests.

Generate non-secret provider overlays:

```bash
./scripts/render-workload-values.sh
```

## Kafka Streams engine

Merge `generated/openworkflow-kafka-streams.environment.yaml` into a registered
environment in the Kafka Streams repository. Add tenant host/DID data and real
immutable image digests, then use that repository's validation and install
scripts:

```bash
cd ../openworkflow-kafka-streams
./deploy/helmfile/validate.sh <environment>
./deploy/helmfile/install.sh <environment>
```

The generated overlay selects the shared Kafka bootstrap service, Cloud SQL
database, Keycloak realm, Gateway, and Secret Manager keys. Its prerequisites
chart creates the namespace-local `oks-database` Secret. Because registry
credentials are environment-specific, image-pull ExternalSecret creation is
disabled until a registry secret is configured.

The default public host emitted by the generator is
`kafka.<root-domain>`; create its DNS record at the Terraform `gateway_ip`.

## Actor engine

The bootstrap owns
`openworkflow-actor-engine/openworkflow-database`. Install the actor chart with
the generated values plus environment-specific image digests:

```bash
cd ../openworkflow-actor-engine
helm upgrade --install openworkflow deploy/helm/openworkflow-actor-engine \
  --namespace openworkflow-actor-engine \
  --values deploy/helm/openworkflow-actor-engine/production-values.yaml \
  --values ../openworkflow-k8s-setup/generated/openworkflow-actor-engine.values.yaml \
  --set imagePolicy.requireDigest=true
```

Set `runtime`, `operations`, `studio`, and migration image repositories/digests
as documented by the actor-engine deployment runbook. The generated HTTPRoute
publishes its runtime service at `actor.<root-domain>`; create DNS accordingly.

## Coexistence

The engines use separate namespaces and databases. They share Keycloak, the
Gateway, and monitoring. Only the Kafka Streams engine consumes the shared
Kafka cluster. Both runtime namespaces have Istio injection and strict mTLS;
their own charts remain responsible for NetworkPolicy and workload RBAC.
