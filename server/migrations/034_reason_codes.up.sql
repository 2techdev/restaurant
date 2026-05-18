-- Migration 034 — Void & Discount reason codes
--
-- Two tenant-scoped reason-code dictionaries used by the POS at checkout time:
--   • void_reasons     — why a line/ticket was voided
--   • discount_reasons — why a manual discount was applied (with optional cap)
--
-- Labels are stored as a jsonb map keyed by ISO locale so the same row can
-- render in tr/de/en/fr/it without a separate i18n table. Optional
-- requires_approval forces a manager-PIN confirmation in the POS UI; the
-- discount table also carries an optional max_discount_percent so a waiter
-- can't apply a 100% discount through a "VIP" reason.
--
-- A small seed of common Swiss-pilot reasons is inserted for every tenant
-- that already exists (Burger House / Pizzeria Da Mario / Sushi Zen) so the
-- POS isn't staring at an empty picker on first open.

BEGIN;

CREATE TABLE IF NOT EXISTS void_reasons (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code             text NOT NULL,
  labels           jsonb NOT NULL DEFAULT '{}'::jsonb,
  requires_approval boolean NOT NULL DEFAULT false,
  display_order    int NOT NULL DEFAULT 0,
  is_active        boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, code)
);
CREATE INDEX IF NOT EXISTS void_reasons_tenant_idx
  ON void_reasons(tenant_id, display_order, is_active);

CREATE TABLE IF NOT EXISTS discount_reasons (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code                  text NOT NULL,
  labels                jsonb NOT NULL DEFAULT '{}'::jsonb,
  requires_approval     boolean NOT NULL DEFAULT false,
  max_discount_percent  numeric(5,2),
  display_order         int NOT NULL DEFAULT 0,
  is_active             boolean NOT NULL DEFAULT true,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, code),
  CHECK (max_discount_percent IS NULL OR (max_discount_percent > 0 AND max_discount_percent <= 100))
);
CREATE INDEX IF NOT EXISTS discount_reasons_tenant_idx
  ON discount_reasons(tenant_id, display_order, is_active);

-- Seed a default set for every existing tenant. Idempotent on (tenant_id,code).
INSERT INTO void_reasons (tenant_id, code, labels, display_order, requires_approval)
SELECT t.id, v.code, v.labels::jsonb, v.ord, v.req
  FROM tenants t,
       (VALUES
         ('CUSTOMER_LEFT',  '{"tr":"Müşteri vazgeçti","de":"Gast hat verzichtet","en":"Customer left","fr":"Client a annulé","it":"Cliente ha rinunciato"}', 10, false),
         ('WRONG_ORDER',    '{"tr":"Yanlış sipariş","de":"Falsche Bestellung","en":"Wrong order","fr":"Commande erronée","it":"Ordine errato"}',           20, false),
         ('QUALITY_ISSUE',  '{"tr":"Kalite sorunu","de":"Qualitätsproblem","en":"Quality issue","fr":"Problème de qualité","it":"Problema di qualità"}',   30, false),
         ('STAFF_ERROR',    '{"tr":"Personel hatası","de":"Personalfehler","en":"Staff error","fr":"Erreur du personnel","it":"Errore del personale"}',     40, true),
         ('TEST_ORDER',     '{"tr":"Test siparişi","de":"Testbestellung","en":"Test order","fr":"Commande de test","it":"Ordine di prova"}',                90, true)
       ) AS v(code, labels, ord, req)
 WHERE COALESCE(t.is_deleted,false)=false
ON CONFLICT (tenant_id, code) DO NOTHING;

INSERT INTO discount_reasons (tenant_id, code, labels, display_order, requires_approval, max_discount_percent)
SELECT t.id, d.code, d.labels::jsonb, d.ord, d.req, d.cap
  FROM tenants t,
       (VALUES
         ('VIP_CUSTOMER',  '{"tr":"VIP indirim","de":"VIP-Rabatt","en":"VIP discount","fr":"Remise VIP","it":"Sconto VIP"}',                                  10, true,  50.0),
         ('REFUND',        '{"tr":"İade","de":"Rückerstattung","en":"Refund","fr":"Remboursement","it":"Rimborso"}',                                          20, true, 100.0),
         ('STAFF_MEAL',    '{"tr":"Personel yemeği","de":"Mitarbeiteressen","en":"Staff meal","fr":"Repas du personnel","it":"Pasto del personale"}',         30, true, 100.0),
         ('HAPPY_HOUR',    '{"tr":"Happy hour","de":"Happy Hour","en":"Happy hour","fr":"Happy hour","it":"Happy hour"}',                                     40, false, 30.0),
         ('LOYALTY',       '{"tr":"Sadakat indirimi","de":"Treuerabatt","en":"Loyalty discount","fr":"Remise fidélité","it":"Sconto fedeltà"}',               50, false, 25.0),
         ('PROMOTIONAL',   '{"tr":"Tanıtım/Kampanya","de":"Werbeaktion","en":"Promotional","fr":"Promotion","it":"Promozionale"}',                            60, false, 50.0)
       ) AS d(code, labels, ord, req, cap)
 WHERE COALESCE(t.is_deleted,false)=false
ON CONFLICT (tenant_id, code) DO NOTHING;

COMMIT;
