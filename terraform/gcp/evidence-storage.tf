# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements. See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
#  the License. You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Evidence bytes are owned by FEI, separate from FOWF protocol-overflow storage.
resource "google_storage_bucket" "entity_intelligence_evidence" {
  for_each = { for key, identity in var.workload_identities : key => identity if key == "entity_intelligence" }

  project                     = var.project_id
  name                        = "${var.project_id}-fei-evidence-${substr(sha256(var.name), 0, 8)}"
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  versioning { enabled = true }
}

resource "google_storage_bucket_iam_member" "entity_intelligence_evidence" {
  for_each = google_storage_bucket.entity_intelligence_evidence
  bucket   = each.value.name
  role     = "roles/storage.objectAdmin"
  member   = "serviceAccount:${google_service_account.workload[each.key].email}"
}

output "entity_intelligence_evidence_buckets" {
  value = { for key, bucket in google_storage_bucket.entity_intelligence_evidence : key => bucket.name }
}
