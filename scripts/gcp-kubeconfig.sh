#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tf_dir="${repo_root}/terraform/gcp"

project_id=$(tofu -chdir="${tf_dir}" output -raw project_id)
cluster_name=$(tofu -chdir="${tf_dir}" output -raw cluster_name)
cluster_location=$(tofu -chdir="${tf_dir}" output -raw cluster_location)

gcloud container clusters get-credentials "${cluster_name}" \
  --project "${project_id}" \
  --region "${cluster_location}"

kubectl cluster-info
