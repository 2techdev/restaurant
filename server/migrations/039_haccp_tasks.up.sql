-- ---------------------------------------------------------------------------
-- 039 — HACCP Digital Checklist Module
--
-- CH/EU regulatory: every food-service operator must keep verifiable
-- temperature, cleaning, opening and closing checklists. Paper logs are
-- still legal but enforcement increasingly expects digital, time-stamped
-- trails. This module captures that workflow.
--
-- Three tables form a small templated workflow engine:
--
--   task_templates   — what to do, scheduled on a CRON
--   task_instances   — one row per scheduled occurrence
--   task_alerts      — out-of-range / missing / late triggers
--
-- HACCP audit-trail rule: once an instance is `completed`, its
-- items_data MUST NOT change. Only correction notes (`correction_notes`
-- column on the instance) can be appended afterwards. The application
-- layer is responsible for enforcing this; the schema records the
-- intent via the `is_locked` flag set on completion.
--
-- All tables tenant-scoped. JSONB used for the multi-language labels
-- and for the variable-shape items / submitted values.
-- ---------------------------------------------------------------------------

-- 1. Templates — operator-authored checklist definitions.
CREATE TABLE IF NOT EXISTS task_templates (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

    -- Localized name/description. JSONB shape: {"de": "...", "en": "..."}.
    -- The `name` plain TEXT column kept for cheap default-language reads.
    name            TEXT NOT NULL,
    name_jsonb      JSONB NOT NULL DEFAULT '{}'::jsonb,
    description     TEXT,
    description_jsonb JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- Buckets the template into a HACCP category so reports can group:
    --   opening | closing | temperature | cleaning | delivery | custom
    category        TEXT NOT NULL DEFAULT 'custom'
        CHECK (category IN ('opening','closing','temperature','cleaning','delivery','custom')),

    -- Schedule. Standard 5-field CRON expression interpreted in the
    -- restaurant's local time zone. Examples:
    --   '0 6 * * *'    every day at 06:00
    --   '0 */1 * * *'  hourly on the hour
    --   '0 23 * * *'   every day at 23:00
    schedule_cron   TEXT NOT NULL DEFAULT '0 6 * * *',

    -- Items definition. Array of objects:
    --   {"id":"i1","type":"checkbox","label":{"de":"...","en":"..."},
    --    "required":true,"validation":{"min":4,"max":7}}
    -- type ∈ checkbox | number | temperature | photo | signature | text
    items_jsonb     JSONB NOT NULL DEFAULT '[]'::jsonb,

    -- Soft on/off toggle. Disabled templates stop generating new instances
    -- but historical instances remain queryable for audit.
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Stored as a plain UUID — the author may live in either `app_users`
    -- (admin) or `users` (POS staff). The app layer keeps the foreign
    -- relationship; no FK constraint here so the schema is agnostic.
    created_by_user_id UUID,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_task_templates_tenant
    ON task_templates(tenant_id) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_task_templates_tenant_active
    ON task_templates(tenant_id, is_active) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_task_templates_category
    ON task_templates(tenant_id, category) WHERE is_deleted = FALSE;

-- 2. Instances — one row per scheduled occurrence of a template.
-- The cron evaluator (server/internal/tasks/cron.go) creates these every
-- few minutes; a staff member then completes the items_data payload.
CREATE TABLE IF NOT EXISTS task_instances (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id     UUID NOT NULL REFERENCES task_templates(id) ON DELETE CASCADE,
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

    -- When this instance was scheduled for (rounded to the minute the cron
    -- fired). Used both for the dashboard "today" view and for the
    -- missed-instance alerter.
    scheduled_for   TIMESTAMPTZ NOT NULL,

    -- pending → in_progress → completed
    -- missed is set by the late-detector once the deadline passes
    -- without completion. Cancelled instances are dropped from reports
    -- but kept on the audit timeline.
    status          TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','in_progress','completed','missed','cancelled')),

    -- The submitted items. Array of {"item_id","value","notes","photo_url"}.
    -- For temperature items, value is the °C reading. For checkbox, value
    -- is "true"/"false". For photo, photo_url is the uploaded path.
    items_data_jsonb JSONB NOT NULL DEFAULT '[]'::jsonb,

    -- Filled when staff submits. After this point items_data is immutable
    -- per HACCP rule; only correction_notes may be appended. user_id is
    -- not constrained — see template note above; the submitter is usually
    -- POS staff in `users` but may be an admin in `app_users`.
    completed_at         TIMESTAMPTZ,
    completed_by_user_id UUID,

    -- Append-only correction trail. JSONB array of
    --   {"at":"2026-05-18T08:00Z","user_id":"...","note":"..."}
    -- so the original record stays intact while the operator can still
    -- annotate after the fact (regulator-visible).
    correction_notes JSONB NOT NULL DEFAULT '[]'::jsonb,

    -- Once locked the application refuses item edits.
    is_locked       BOOLEAN NOT NULL DEFAULT FALSE,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- One instance per (template, scheduled_for) so the cron evaluator
    -- can be re-run safely without duplicating rows.
    UNIQUE (template_id, scheduled_for)
);

CREATE INDEX IF NOT EXISTS idx_task_instances_tenant_scheduled
    ON task_instances(tenant_id, scheduled_for DESC);
CREATE INDEX IF NOT EXISTS idx_task_instances_status
    ON task_instances(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_task_instances_template
    ON task_instances(template_id, scheduled_for DESC);

-- 3. Alerts — surfaced anomalies. Generated by:
--   • cron late-detector  (alert_type = 'missing' / 'late')
--   • complete handler   (alert_type = 'out_of_range') when a
--     temperature reading falls outside the template's allowed range.
CREATE TABLE IF NOT EXISTS task_alerts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    instance_id     UUID NOT NULL REFERENCES task_instances(id) ON DELETE CASCADE,
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

    -- Free-form item id (matches the template's items_jsonb[].id). NULL
    -- for instance-level alerts like "missing".
    item_id         TEXT,

    alert_type      TEXT NOT NULL
        CHECK (alert_type IN ('out_of_range','missing','late','validation_failed')),

    -- Human-readable message in the restaurant's primary language.
    -- For multi-lang we'd carry a JSONB; alerts are operator-internal
    -- so single language is fine.
    message         TEXT NOT NULL,

    -- Severity for the dashboard banner / sort. info < warn < critical.
    severity        TEXT NOT NULL DEFAULT 'warn'
        CHECK (severity IN ('info','warn','critical')),

    resolved_at         TIMESTAMPTZ,
    resolved_by_user_id UUID,
    resolution_note     TEXT,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_task_alerts_tenant_open
    ON task_alerts(tenant_id, created_at DESC) WHERE resolved_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_task_alerts_instance
    ON task_alerts(instance_id);

-- 4. Per-tenant feature toggle. Lives on tenants — same pattern as the
-- other module switches (kds_enabled, reservations_enabled, …). Default
-- FALSE keeps existing tenants untouched until an admin opts in.
ALTER TABLE tenants
    ADD COLUMN IF NOT EXISTS tasks_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- 5. Seed five HACCP-standard default templates for every existing tenant.
-- Idempotent on (tenant_id, name) using a manual EXISTS guard so a
-- re-applied migration doesn't duplicate the seeds. Translations cover
-- the five UI locales (de/en/fr/it/tr); DE is the primary CH form so
-- regulator-facing labels read naturally on a printed audit.
INSERT INTO task_templates
    (id, tenant_id, name, name_jsonb, description, description_jsonb,
     category, schedule_cron, items_jsonb, is_active)
SELECT
    gen_random_uuid(),
    t.id,
    seed.name,
    seed.name_jsonb,
    seed.description,
    seed.description_jsonb,
    seed.category,
    seed.schedule_cron,
    seed.items_jsonb,
    TRUE
FROM tenants t
CROSS JOIN (VALUES
    -- ──────────────────────────────────────────────────────────────────
    -- 1. Opening checklist — 06:00 every morning
    -- ──────────────────────────────────────────────────────────────────
    (
        'Sabah Açılış',
        '{"de":"Morgenöffnung","en":"Morning Opening","fr":"Ouverture du matin","it":"Apertura mattutina","tr":"Sabah Açılış"}'::jsonb,
        'Lokal hijyen + ekipman kontrolü',
        '{"de":"Hygiene + Geräte-Kontrolle","en":"Hygiene + equipment check","fr":"Hygiène + contrôle équipement","it":"Igiene + controllo attrezzature","tr":"Lokal hijyen + ekipman kontrolü"}'::jsonb,
        'opening',
        '0 6 * * *',
        '[
          {"id":"o1","type":"checkbox","required":true,
            "label":{"de":"Hände gewaschen + Handschuhe getragen","en":"Hands washed + gloves on","fr":"Mains lavées + gants","it":"Mani lavate + guanti","tr":"Eller yıkandı + eldiven takıldı"}},
          {"id":"o2","type":"temperature","required":true,
            "label":{"de":"Kühlschrank Temperatur","en":"Fridge temperature","fr":"Température réfrigérateur","it":"Temperatura frigorifero","tr":"Buzdolabı sıcaklığı"},
            "validation":{"min":2,"max":7,"unit":"C"}},
          {"id":"o3","type":"checkbox","required":true,
            "label":{"de":"Gerätekontrolle (Herd, Ofen, Grill)","en":"Equipment check (stove, oven, grill)","fr":"Contrôle équipement","it":"Controllo attrezzature","tr":"Ekipman kontrolü (ocak, fırın, ızgara)"}}
        ]'::jsonb
    ),
    -- ──────────────────────────────────────────────────────────────────
    -- 2. Closing checklist — 23:00 every evening
    -- ──────────────────────────────────────────────────────────────────
    (
        'Akşam Kapanış',
        '{"de":"Abendschliessung","en":"Evening Closing","fr":"Fermeture du soir","it":"Chiusura serale","tr":"Akşam Kapanış"}'::jsonb,
        'Temizlik + ısı + soğutma kapanış kontrolleri',
        '{"de":"Reinigung + Temperatur + Kühlung","en":"Cleaning + temperature + refrigeration","fr":"Nettoyage + température + réfrigération","it":"Pulizia + temperatura + refrigerazione","tr":"Temizlik + ısı + soğutma"}'::jsonb,
        'closing',
        '0 23 * * *',
        '[
          {"id":"c1","type":"checkbox","required":true,
            "label":{"de":"Arbeitsflächen gereinigt","en":"Surfaces cleaned","fr":"Surfaces nettoyées","it":"Superfici pulite","tr":"Tezgahlar temizlendi"}},
          {"id":"c2","type":"temperature","required":true,
            "label":{"de":"Tiefkühlfach Temperatur","en":"Freezer temperature","fr":"Température congélateur","it":"Temperatura congelatore","tr":"Deep freezer sıcaklığı"},
            "validation":{"min":-25,"max":-18,"unit":"C"}},
          {"id":"c3","type":"checkbox","required":true,
            "label":{"de":"Müll entsorgt","en":"Waste removed","fr":"Déchets retirés","it":"Rifiuti smaltiti","tr":"Çöp atıldı"}},
          {"id":"c4","type":"signature","required":true,
            "label":{"de":"Unterschrift Schichtleiter","en":"Shift manager signature","fr":"Signature responsable","it":"Firma responsabile","tr":"Vardiya sorumlusu imzası"}}
        ]'::jsonb
    ),
    -- ──────────────────────────────────────────────────────────────────
    -- 3. Hourly temperature log — every hour 06:00–23:00
    -- ──────────────────────────────────────────────────────────────────
    (
        'Sıcaklık Saati',
        '{"de":"Stündliche Temperatur","en":"Hourly Temperature","fr":"Température horaire","it":"Temperatura oraria","tr":"Sıcaklık Saati"}'::jsonb,
        'Her saat soğuk depo + deep freezer + soğuk vitrin',
        '{"de":"Kühllager + Tiefkühl + Vitrine — stündlich","en":"Cold storage + freezer + display — hourly","fr":"Stockage froid + congélateur + vitrine","it":"Magazzino freddo + congelatore + vetrina","tr":"Soğuk depo + deep freezer + vitrin"}'::jsonb,
        'temperature',
        '0 6-23 * * *',
        '[
          {"id":"t1","type":"temperature","required":true,
            "label":{"de":"Kühllager","en":"Cold storage","fr":"Stockage froid","it":"Magazzino freddo","tr":"Soğuk depo"},
            "validation":{"min":2,"max":7,"unit":"C"}},
          {"id":"t2","type":"temperature","required":true,
            "label":{"de":"Tiefkühlfach","en":"Freezer","fr":"Congélateur","it":"Congelatore","tr":"Deep freezer"},
            "validation":{"min":-25,"max":-18,"unit":"C"}},
          {"id":"t3","type":"temperature","required":false,
            "label":{"de":"Verkaufsvitrine","en":"Display fridge","fr":"Vitrine réfrigérée","it":"Vetrina refrigerata","tr":"Soğuk vitrin"},
            "validation":{"min":4,"max":8,"unit":"C"}}
        ]'::jsonb
    ),
    -- ──────────────────────────────────────────────────────────────────
    -- 4. Shift-end kitchen cleaning — twice a day at 15:00 and 23:00
    -- ──────────────────────────────────────────────────────────────────
    (
        'Vardiya Sonu Mutfak',
        '{"de":"Schichtende Küche","en":"Shift-end Kitchen","fr":"Fin de service cuisine","it":"Fine turno cucina","tr":"Vardiya Sonu Mutfak"}'::jsonb,
        'Vardiya sonu mutfak temizlik kontrol listesi',
        '{"de":"Reinigungs-Checkliste am Schichtende","en":"Shift-end cleaning checklist","fr":"Checklist nettoyage fin de service","it":"Checklist pulizie fine turno","tr":"Vardiya sonu temizlik checklist"}'::jsonb,
        'cleaning',
        '0 15,23 * * *',
        '[
          {"id":"s1","type":"checkbox","required":true,
            "label":{"de":"Ofen gereinigt","en":"Oven cleaned","fr":"Four nettoyé","it":"Forno pulito","tr":"Fırın temizlendi"}},
          {"id":"s2","type":"checkbox","required":true,
            "label":{"de":"Friteuse Öl gefiltert","en":"Fryer oil filtered","fr":"Huile friteuse filtrée","it":"Olio friggitrice filtrato","tr":"Fritöz yağı süzüldü"}},
          {"id":"s3","type":"checkbox","required":true,
            "label":{"de":"Boden gewischt","en":"Floor mopped","fr":"Sol nettoyé","it":"Pavimento pulito","tr":"Zemin paspaslandı"}},
          {"id":"s4","type":"photo","required":false,
            "label":{"de":"Foto Endzustand","en":"Photo of final state","fr":"Photo état final","it":"Foto stato finale","tr":"Son durum fotoğrafı"}}
        ]'::jsonb
    ),
    -- ──────────────────────────────────────────────────────────────────
    -- 5. Delivery / receiving check — manual trigger (no fixed time;
    --    we still register a 'never' cron and operators run it on
    --    demand via the POS "Add ad-hoc instance" action.)
    --    Use 0 0 31 2 * — Feb 31st never fires; instance is created
    --    by the operator manually. This avoids unwanted scheduling.
    -- ──────────────────────────────────────────────────────────────────
    (
        'Tedarik Kabul',
        '{"de":"Wareneingang","en":"Goods Receiving","fr":"Réception marchandises","it":"Ricevimento merci","tr":"Tedarik Kabul"}'::jsonb,
        'Gelen mal kontrolü (sıcaklık, lot, son kullanma)',
        '{"de":"Kontrolle eingehender Ware (Temperatur, Lot, MHD)","en":"Inspect incoming goods (temperature, lot, expiry)","fr":"Contrôle marchandises entrantes","it":"Controllo merci in entrata","tr":"Gelen mal kontrolü (sıcaklık, lot, son kullanma)"}'::jsonb,
        'delivery',
        '0 0 31 2 *',
        '[
          {"id":"d1","type":"text","required":true,
            "label":{"de":"Lieferant","en":"Supplier","fr":"Fournisseur","it":"Fornitore","tr":"Tedarikçi"}},
          {"id":"d2","type":"temperature","required":true,
            "label":{"de":"Wareneingangstemperatur","en":"Incoming temperature","fr":"Température à réception","it":"Temperatura ricezione","tr":"Kabul sıcaklığı"},
            "validation":{"min":0,"max":7,"unit":"C"}},
          {"id":"d3","type":"text","required":true,
            "label":{"de":"Lot / MHD","en":"Lot / expiry","fr":"Lot / DLC","it":"Lotto / scadenza","tr":"Lot / son kullanma"}},
          {"id":"d4","type":"photo","required":false,
            "label":{"de":"Foto Lieferschein","en":"Photo of delivery note","fr":"Photo bon de livraison","it":"Foto bolla","tr":"İrsaliye fotoğrafı"}}
        ]'::jsonb
    )
) AS seed(name, name_jsonb, description, description_jsonb, category, schedule_cron, items_jsonb)
WHERE NOT EXISTS (
    SELECT 1 FROM task_templates ex
    WHERE ex.tenant_id = t.id AND ex.name = seed.name AND ex.is_deleted = FALSE
);
