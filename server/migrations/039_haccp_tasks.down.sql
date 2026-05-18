-- 039 — rollback HACCP tasks module.
DROP TRIGGER IF EXISTS trg_seed_haccp_on_tenant_insert ON tenants;
DROP FUNCTION IF EXISTS tg_seed_haccp_on_tenant_insert();
DROP FUNCTION IF EXISTS seed_default_haccp_templates(UUID);
ALTER TABLE tenants DROP COLUMN IF EXISTS tasks_enabled;
DROP TABLE IF EXISTS task_alerts;
DROP TABLE IF EXISTS task_instances;
DROP TABLE IF EXISTS task_templates;
