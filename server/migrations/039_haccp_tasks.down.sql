-- 039 — rollback HACCP tasks module.
ALTER TABLE tenants DROP COLUMN IF EXISTS tasks_enabled;
DROP TABLE IF EXISTS task_alerts;
DROP TABLE IF EXISTS task_instances;
DROP TABLE IF EXISTS task_templates;
