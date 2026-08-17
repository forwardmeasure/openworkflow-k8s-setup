#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tf_dir="${repo_root}/terraform/aws"

cluster_name=$(tofu -chdir="${tf_dir}" output -raw cluster_name)
cluster_location=$(tofu -chdir="${tf_dir}" output -raw cluster_location)

aws eks update-kubeconfig --name "${cluster_name}" --region "${cluster_location}"
kubectl cluster-info
