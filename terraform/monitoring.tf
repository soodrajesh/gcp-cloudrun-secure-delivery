resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "Secure delivery alerts"
  type         = "email"
  labels       = { email_address = var.alert_email }
  depends_on   = [google_project_service.apis]
}

resource "google_monitoring_alert_policy" "prod_5xx" {
  project      = var.project_id
  display_name = "Delivery: quote-prod 5xx ratio > 5% (canary or release is bad)"
  combiner     = "OR"
  conditions {
    display_name = "5xx / all requests > 5 % over 2 min"
    condition_threshold {
      filter             = "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"quote-prod\" AND metric.label.response_code_class=\"5xx\""
      denominator_filter = "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"quote-prod\""
      comparison         = "COMPARISON_GT"
      threshold_value    = 0.05
      duration           = "120s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
      denominator_aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  notification_channels = [google_monitoring_notification_channel.email.id]
  documentation {
    content   = "Roll back: gcloud deploy targets rollback prod --delivery-pipeline quote. Runbook: docs/runbooks/05-release-and-rollback.md"
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_dashboard" "main" {
  project = var.project_id
  dashboard_json = jsonencode({
    displayName = "Secure delivery"
    mosaicLayout = {
      columns = 12
      tiles = [
        { width = 6, height = 4, widget = { title = "quote-prod requests by revision (per min)", xyChart = { dataSets = [{ plotType = "STACKED_AREA", timeSeriesQuery = { timeSeriesFilter = { filter = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" resource.label.service_name=\"quote-prod\"", aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_RATE", groupByFields = ["resource.label.revision_name"], crossSeriesReducer = "REDUCE_SUM" } } } }] } } },
        { xPos = 6, width = 6, height = 4, widget = { title = "quote-prod 5xx by revision (per min)", xyChart = { dataSets = [{ plotType = "STACKED_BAR", timeSeriesQuery = { timeSeriesFilter = { filter = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" resource.label.service_name=\"quote-prod\" metric.label.response_code_class=\"5xx\"", aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_RATE", groupByFields = ["resource.label.revision_name"], crossSeriesReducer = "REDUCE_SUM" } } } }] } } },
        { yPos = 4, width = 12, height = 4, widget = { title = "Latency p95 (ms) by service", xyChart = { dataSets = [{ plotType = "LINE", timeSeriesQuery = { timeSeriesFilter = { filter = "metric.type=\"run.googleapis.com/request_latencies\" resource.type=\"cloud_run_revision\"", aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_PERCENTILE_95", groupByFields = ["resource.label.service_name"], crossSeriesReducer = "REDUCE_MAX" } } } }] } } },
      ]
    }
  })
  depends_on = [google_project_service.apis]
}

resource "google_billing_budget" "this" {
  billing_account = var.billing_account_id
  display_name    = "cloudrun-secure-delivery"
  amount {
    specified_amount {
      currency_code = "EUR"
      units         = tostring(var.budget_amount)
    }
  }
  budget_filter {
    projects = ["projects/${data.google_project.this.number}"]
  }
  threshold_rules { threshold_percent = 0.5 }
  threshold_rules { threshold_percent = 1.0 }
  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.email.id]
    disable_default_iam_recipients   = true
  }
  depends_on = [google_project_service.apis]
}
