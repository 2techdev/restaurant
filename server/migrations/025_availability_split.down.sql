-- Down 025: drop availability split columns
ALTER TABLE products
    DROP COLUMN IF EXISTS is_online_visible,
    DROP COLUMN IF EXISTS is_available;
