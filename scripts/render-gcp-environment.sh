#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tf_dir="${repo_root}/terraform/gcp"
target="${repo_root}/bootstrap/environments/gcp.generated.yaml"
outputs=$(tofu -chdir="${tf_dir}" output -json)

jq -n --argjson tf "${outputs}" '
  {
    gcp: {
      projectId: $tf.project_id.value
    },
    externalSecrets: {
      storeName: "google-secret-manager",
      serviceAccountAnnotations: {
        "iam.gke.io/gcp-service-account": $tf.external_secrets_service_account_email.value
      },
      provider: {
        gcpsm: {projectID: $tf.project_id.value}
      }
    },
    rootDomain: $tf.root_domain.value,
    authHostname: ("auth." + $tf.root_domain.value),
    gatewayIp: $tf.gateway_ip.value,
    cloudsqlPrivateIp: $tf.cloudsql_private_ip.value,
    acmeEmail: $tf.acme_email.value,
    acmeServer: $tf.acme_server.value,
    keycloakReplicas: $tf.keycloak_replicas.value,
    kafkaStorageSize: $tf.kafka_storage_size.value,
    observability: {enabled: $tf.observability_enabled.value},
    secrets: {
      keycloakDatabase: $tf.secret_ids.value.keycloak_database,
      keycloakAdmin: $tf.secret_ids.value.keycloak_admin,
      kafkaStreamsDatabase: $tf.secret_ids.value.kafka_streams_database,
      actorEngineDatabase: $tf.secret_ids.value.actor_engine_database
    },
    databases: {
      keycloak: $tf.database_names.value.keycloak,
      kafkaStreams: $tf.database_names.value.kafka_streams,
      actorEngine: $tf.database_names.value.actor_engine
    },
    databaseUsers: {
      keycloak: $tf.database_usernames.value.keycloak,
      kafkaStreams: $tf.database_usernames.value.kafka_streams,
      actorEngine: $tf.database_usernames.value.actor_engine
    }
  }
' >"${target}"

echo "Wrote ${target} (non-secret values only)."
