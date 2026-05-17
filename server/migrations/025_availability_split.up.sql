-- Migration 025: 3-axis availability split
-- ChatGPT brief Aşama 4 — `is_active` (catalog), `is_available` (sold-out),
-- `is_online_visible` (online channel) ayrı kavramlar.
--
-- products.is_active zaten var (catalog flag).
-- Bu migration:
--   products.is_available BOOLEAN NOT NULL DEFAULT TRUE  — sold-out flag
--   products.is_online_visible BOOLEAN NOT NULL DEFAULT TRUE  — online channel toggle
--
-- Default TRUE → mevcut tüm ürünler etkilenmez. Backoffice 3-toggle UI
-- üzerinden yönetilir; POS long-press sold-out kaldırıldı (read-only).

ALTER TABLE products
    ADD COLUMN IF NOT EXISTS is_available BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS is_online_visible BOOLEAN NOT NULL DEFAULT TRUE;
