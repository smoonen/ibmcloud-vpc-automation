# Create IAM authorizations enabling the backup policy to manage snapshots
# It would be nice to be able to scope these to our resource group, but internal
# checks on creation of the backup policy prevent us from doing so.
resource "ibm_iam_authorization_policy" "volume_policy" {
  source_service_name      = "is"
  source_resource_type     = "backup-policy"

  resource_attributes {
    name     = "accountId"
    value    = ibm_iam_account_settings.settings.id
  }
  resource_attributes {
    name     = "serviceName"
    value    = "is"
  }
  resource_attributes {
    name     = "volumeId"
    operator = "stringExists"
    value    = "true"
  }

  roles = ["Operator"]
}

resource "ibm_iam_authorization_policy" "snapshot_policy" {
  source_service_name      = "is"
  source_resource_type     = "backup-policy"

  resource_attributes {
    name     = "accountId"
    value    = ibm_iam_account_settings.settings.id
  }
  resource_attributes {
    name     = "serviceName"
    value    = "is"
  }
  resource_attributes {
    name     = "snapshotId"
    operator = "stringExists"
    value    = "true"
  }

  roles = ["Editor"]
}

resource "ibm_iam_authorization_policy" "cgroup_policy" {
  source_service_name      = "is"
  source_resource_type     = "backup-policy"

  resource_attributes {
    name     = "accountId"
    value    = ibm_iam_account_settings.settings.id
  }
  resource_attributes {
    name     = "serviceName"
    value    = "is"
  }
  resource_attributes {
    name     = "snapshotConsistencyGroupId"
    operator = "stringExists"
    value    = "true"
  }

  roles = ["Editor"]
}

resource "ibm_iam_authorization_policy" "instance_policy" {
  source_service_name      = "is"
  source_resource_type     = "backup-policy"

  resource_attributes {
    name     = "accountId"
    value    = ibm_iam_account_settings.settings.id
  }
  resource_attributes {
    name     = "serviceName"
    value    = "is"
  }
  resource_attributes {
    name     = "instanceId"
    operator = "stringExists"
    value    = "true"
  }

  roles = ["Operator"]
}

# Snapshot volumes for the tagged database instances
resource "ibm_is_backup_policy" "policy" {
  name                = "${var.prefix}-policy"
  resource_group      = ibm_resource_group.resource_group.id

  match_resource_type = "volume"
  match_user_tags     = ["${var.prefix}-primarybackup", "${var.prefix}-standbybackup"]
}

resource "ibm_is_backup_policy_plan" "plan" {
  name             = "${var.prefix}-plan"
  backup_policy_id = ibm_is_backup_policy.policy.id
  cron_spec        = "5 * * * *"
  copy_user_tags   = true

  deletion_trigger {
    delete_over_count = 3
  }

  remote_region_policy {
    delete_over_count = 3
    region            = var.secondary_region
  }
}

