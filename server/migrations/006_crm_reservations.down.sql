-- Migration 006 rollback: remove CRM and reservation tables
DROP TABLE IF EXISTS loyalty_transactions;
DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS customers;
