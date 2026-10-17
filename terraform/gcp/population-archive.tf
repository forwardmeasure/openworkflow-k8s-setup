#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements. See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Uses the same archive module as the platform infrastructure. This adds no Cloud SQL flags.
variable "entity_intelligence_population_archive_storage_class" {
  type    = string
  default = "STANDARD"
}

module "entity_intelligence_population_archive" {
  count  = contains(keys(var.workload_identities), "entity_intelligence") ? 1 : 0
  source = "../../../forwardmeasure-platform/k8s-infrastructure/opentofu/gcp/modules/population-archive"

  project_id              = var.project_id
  region                  = var.region
  cluster_id              = var.name
  runtime_service_account = google_service_account.workload["entity_intelligence"].email
  storage_class           = var.entity_intelligence_population_archive_storage_class

  depends_on = [google_project_service.required]
}

output "entity_intelligence_population_archive" {
  value = one(module.entity_intelligence_population_archive)
}
