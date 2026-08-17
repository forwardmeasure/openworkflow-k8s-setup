#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tf_dir="${repo_root}/terraform/azure"

resource_group_name=$(tofu -chdir="${tf_dir}" output -raw resource_group_name)
cluster_name=$(tofu -chdir="${tf_dir}" output -raw cluster_name)

az aks get-credentials --resource-group "${resource_group_name}" --name "${cluster_name}"
kubectl cluster-info
