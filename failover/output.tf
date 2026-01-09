# Output the capture timestamps for the primary and secondary database nodes

output db_primary_capture_timestamp {
  value = local.primary_snapshot.captured_at
}

output db_standby_capture_timestamp {
  value = local.standby_snapshot.captured_at
}

