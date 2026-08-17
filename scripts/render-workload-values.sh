#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tf_dir="${repo_root}/terraform/gcp"
target_dir="${repo_root}/generated"
outputs=$(tofu -chdir="${tf_dir}" output -json)
mkdir -p "${target_dir}"

jq -n --argjson tf "${outputs}" '
  ($tf.root_domain.value) as $domain |
  ($tf.cloudsql_private_ip.value) as $db |
  {
    identity: {
      issuer: ("https://auth." + $domain + "/realms/openworkflow"),
      persistedName: "keycloak",
      browserUrl: ("https://auth." + $domain),
      realm: "openworkflow",
      clientId: "openworkflow-public",
      audience: "oks-api"
    },
    database: {
      jdbcUrl: ("jdbc:postgresql://" + $db + ":5432/" + $tf.database_names.value.kafka_streams)
    },
    networkPolicy: {databaseCidrs: [($db + "/32")]},
    externalSecrets: {
      storeKind: "ClusterSecretStore",
      storeName: "google-secret-manager",
      databaseUsernameRemoteKey: $tf.secret_ids.value.kafka_streams_username,
      databasePasswordRemoteKey: $tf.secret_ids.value.kafka_streams_password,
      imagePullSecretEnabled: false
    },
    kafka: {
      bootstrapServers: "kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092",
      clusterName: "kafka-cluster",
      namespace: "kafka"
    },
    routing: {
      hosts: [("kafka." + $domain)],
      gatewayNamespace: "istio-system",
      gatewayName: "platform-gateway",
      gatewaySectionName: "root-https"
    }
  }
' >"${target_dir}/openworkflow-kafka-streams.environment.yaml"

jq -n --argjson tf "${outputs}" '
  ($tf.root_domain.value) as $domain |
  ($tf.cloudsql_private_ip.value) as $db |
  {
    persistence: {
      profile: "postgresql",
      existingSecret: "openworkflow-database"
    },
    security: {
      oidcIssuer: ("https://auth." + $domain + "/realms/openworkflow"),
      oidcJwksUri: ("https://auth." + $domain + "/realms/openworkflow/protocol/openid-connect/certs"),
      oidcAudience: "openworkflow-actor-engine"
    },
    networkPolicy: {
      enabled: true,
      egress: [{to: [{ipBlock: {cidr: ($db + "/32")}}], ports: [{protocol: "TCP", port: 5432}]}]
    },
    extraObjects: [{
      apiVersion: "gateway.networking.k8s.io/v1",
      kind: "HTTPRoute",
      metadata: {name: "openworkflow-actor-engine"},
      spec: {
        hostnames: [("actor." + $domain)],
        parentRefs: [{name: "platform-gateway", namespace: "istio-system", sectionName: "root-https"}],
        rules: [{backendRefs: [{name: "openworkflow-openworkflow-actor-engine", port: 8080}]}]
      }
    }]
  }
' >"${target_dir}/openworkflow-actor-engine.values.yaml"

echo "Wrote workload overlays under ${target_dir}. No secret values were exported."
