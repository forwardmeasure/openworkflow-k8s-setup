# workload_identities gained support for binding one GSA to more than one
# (namespace, service_account) pair (see additional_bindings in
# variables.tf), which required re-keying google_service_account_iam_member
# from var.workload_identities directly to a flattened
# local.workload_identity_bindings map ("<identity_key>:primary" for the
# first binding, "<identity_key>:<namespace>/<service_account>" for any
# more). Without these moved blocks, Terraform would see the address change
# as an unrelated destroy+create for every already-applied identity, even
# though the underlying IAM binding is unchanged.
moved {
  from = google_service_account_iam_member.workload_identity["runtime"]
  to   = google_service_account_iam_member.workload_identity["runtime:primary"]
}

moved {
  from = google_service_account_iam_member.workload_identity["keycloak"]
  to   = google_service_account_iam_member.workload_identity["keycloak:primary"]
}

moved {
  from = google_service_account_iam_member.workload_identity["superset"]
  to   = google_service_account_iam_member.workload_identity["superset:primary"]
}

moved {
  from = google_service_account_iam_member.workload_identity["nominatim"]
  to   = google_service_account_iam_member.workload_identity["nominatim:primary"]
}

moved {
  from = google_service_account_iam_member.workload_identity["kriyagentic"]
  to   = google_service_account_iam_member.workload_identity["kriyagentic:primary"]
}

moved {
  from = google_service_account_iam_member.workload_identity["migrations"]
  to   = google_service_account_iam_member.workload_identity["migrations:primary"]
}
