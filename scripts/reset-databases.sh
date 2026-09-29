#!/usr/bin/env bash
# Wipes every database and login role on this stack's Cloud SQL instance so Terraform and the
# migration Jobs can recreate them from scratch. Keeps only what Cloud SQL itself creates: the
# `postgres` database and user. Asks you to type the instance name before changing anything. Safe
# to re-run after a partial failure: it re-lists what is still there and drops only that.
#
# Drops run as SQL, connected as the Terraform administrator, from a throwaway psql pod in the
# cluster: the instance has only a private IP, and the Cloud SQL API refuses to delete a database
# not owned by cloudsqlsuperuser (e.g. one a migration Job created or reassigned). The admin
# password is read from Secret Manager in this shell and sent over the pod's stdin - it never
# appears in the pod spec. The administrator itself is dropped last, through the API.
#
# Afterwards: export TF_VAR_cloudsql_user_passwords, `tofu apply` (recreates the declared databases,
# the administrator and the component roles), then install-platform.sh (restores Keycloak/Superset
# and runs the migration Jobs, which create the control-plane tables, product runtime roles and
# tenant databases).
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tf_dir="${repo_root}/terraform/gcp"

connection_name=$(tofu -chdir="${tf_dir}" output -raw database_connection_name)
project_id=${connection_name%%:*}
instance=${connection_name##*:}
administrator=$(tofu -chdir="${tf_dir}" output -json database_administrator_usernames | jq -r '[.[]] | unique | .[0] // empty')
administrator_secret=$(tofu -chdir="${tf_dir}" output -json database_administrator_secret_ids | jq -r '[.[]] | unique | .[0] // empty')
if [[ -z "${administrator}" || -z "${administrator_secret}" ]]; then
  echo "Could not read the administrator username/secret from tofu output - refusing to continue." >&2
  exit 1
fi
private_ip=$(gcloud sql instances describe "${instance}" --project "${project_id}" --format=json |
  jq -r '[.ipAddresses[] | select(.type == "PRIVATE") | .ipAddress][0] // empty')
if [[ -z "${private_ip}" ]]; then
  echo "Instance ${instance} has no private IP - refusing to continue." >&2
  exit 1
fi

# Runs the SQL on stdin as the administrator from a throwaway pod. The password is the first line
# the pod reads from stdin, so it never lands in the pod spec.
run_sql_as_administrator() {
  local sql password secret_project
  sql=$(cat)
  # The tofu output is the full resource name (projects/<project>/secrets/<id>); gcloud wants the
  # bare id plus --project. Read before the pipe so a failed read stops the script (set -e).
  secret_project=${administrator_secret#projects/}
  secret_project=${secret_project%%/*}
  password=$(gcloud secrets versions access latest --secret "${administrator_secret##*/}" --project "${secret_project}")
  if [[ -z "${password}" ]]; then
    echo "Administrator password is empty - refusing to continue." >&2
    exit 1
  fi
  printf '%s\n%s\n' "${password}" "${sql}" | kubectl run "reset-databases-$(date +%s)" --namespace default --image postgres:17-alpine \
    --restart Never --rm -i --quiet \
    --env "PGHOST=${private_ip}" --env PGPORT=5432 --env PGDATABASE=postgres \
    --env "PGUSER=${administrator}" --env PGSSLMODE=require --env PGCONNECT_TIMEOUT=15 \
    --command -- sh -c 'read -r PGPASSWORD; export PGPASSWORD; exec psql -X -v ON_ERROR_STOP=1'
}

quote_identifier() {
  printf '"%s"' "${1//\"/\"\"}"
}

# Every workload holding connections to these databases - DROP DATABASE fails while any are open.
# install-platform.sh (helmfile) restores their replica counts.
consumers=("keycloak statefulset/keycloak" "superset deployment/superset" "superset deployment/superset-worker")

# Listed into variables first so a failed gcloud call stops the script instead of yielding an empty list.
database_names=$(gcloud sql databases list --instance "${instance}" --project "${project_id}" --format='value(name)')
user_names=$(gcloud sql users list --instance "${instance}" --project "${project_id}" --format='value(name)')
mapfile -t databases < <(grep -vx -e postgres -e '' <<<"${database_names}" || true)
# The administrator goes last: it created the other roles (and holds ADMIN on them).
mapfile -t users < <(grep -vx -e postgres -e "${administrator}" -e '' <<<"${user_names}" || true)
if grep -qx "${administrator}" <<<"${user_names}"; then
  users+=("${administrator}")
fi

echo "Cloud SQL instance: ${project_id}/${instance}"
echo "Kubernetes context: $(kubectl config current-context)"
echo "Databases to drop:  ${databases[*]:-<none>}"
echo "Roles to drop:      ${users[*]:-<none>}"
echo "Kept:               database postgres, user postgres"
echo "Workloads stopped:  ${consumers[*]}"
read -r -p "Type the instance name (${instance}) to continue: " answer
if [[ "${answer}" != "${instance}" ]]; then
  echo "Aborted - nothing changed."
  exit 1
fi


echo "1/3 Stopping workloads connected to the databases"
for consumer in "${consumers[@]}"; do
  read -r namespace workload <<<"${consumer}"
  if ! kubectl -n "${namespace}" get "${workload}" >/dev/null 2>&1; then
    continue
  fi
  selector=$(kubectl -n "${namespace}" get "${workload}" -o json |
    jq -r '.spec.selector.matchLabels | to_entries | map("\(.key)=\(.value)") | join(",")')
  kubectl -n "${namespace}" scale "${workload}" --replicas=0
  if [[ -n "$(kubectl -n "${namespace}" get pods -l "${selector}" -o name)" ]]; then
    kubectl -n "${namespace}" wait --for=delete pod -l "${selector}" --timeout=300s
  fi
done

echo "2/3 Dropping databases and roles as ${administrator} (SQL, from a pod in the cluster)"
statements=()
for database in "${databases[@]}"; do
  statements+=("DROP DATABASE IF EXISTS $(quote_identifier "${database}");")
done
for user in "${users[@]}"; do
  if [[ "${user}" != "${administrator}" ]]; then
    statements+=("DROP ROLE IF EXISTS $(quote_identifier "${user}");")
  fi
done
if ((${#statements[@]} > 0)); then
  printf '%s\n' "${statements[@]}" | run_sql_as_administrator
fi

echo "3/3 Dropping ${administrator} (API - a role cannot drop itself)"
if grep -qx "${administrator}" <<<"${user_names}"; then
  gcloud sql users delete "${administrator}" --instance "${instance}" --project "${project_id}" --quiet
fi

echo "Done. Remaining databases: $(gcloud sql databases list --instance "${instance}" --project "${project_id}" --format='value(name)' | tr '\n' ' ')"
echo "Remaining roles:     $(gcloud sql users list --instance "${instance}" --project "${project_id}" --format='value(name)' | tr '\n' ' ')"
