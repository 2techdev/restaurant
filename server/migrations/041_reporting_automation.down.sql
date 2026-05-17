-- Rollback for 041 — reporting automation.
DROP TABLE IF EXISTS alert_logs;
DROP TABLE IF EXISTS threshold_alerts;
DROP TABLE IF EXISTS report_logs;
DROP TABLE IF EXISTS scheduled_reports;
