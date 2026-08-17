#!/usr/bin/env bash
set -euo pipefail

failures=0

check_rollout() {
  local namespace=$1
  local resource=$2
  if ! kubectl -n "${namespace}" rollout status "${resource}" --timeout=5m; then
    failures=$((failures + 1))
  fi
}

kubectl get nodes
check_rollout cert-manager deployment/cert-manager
check_rollout istio-system deployment/istiod
check_rollout external-secrets deployment/external-secrets
check_rollout kafka deployment/strimzi-cluster-operator
check_rollout identity statefulset/keycloak-keycloakx

kubectl -n istio-system get gateway platform-gateway
kubectl -n istio-system get certificate platform-tls
kubectl get clustersecretstore google-secret-manager
kubectl -n kafka get kafka kafka-cluster
kubectl -n identity get externalsecret keycloak-credentials
kubectl -n openworkflow-actor-engine get externalsecret openworkflow-database

if ((failures > 0)); then
  echo "${failures} rollout check(s) failed." >&2
  exit 1
fi

echo "OpenWorkflow platform bootstrap is ready."
