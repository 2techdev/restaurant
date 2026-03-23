#!/usr/bin/env node
/**
 * GastroCore License Generator
 *
 * Generates a signed Ed25519 license token compatible with
 * lib/features/licensing/data/services/license_validator.dart.
 *
 * Token format: Base64url( UTF-8( JSON ) )
 * Signed message: canonical JSON of all fields except "sig",
 *   keys sorted alphabetically, no whitespace, UTF-8 encoded.
 *
 * Usage:
 *   GASTROCORE_PRIVATE_SEED=<hex> node generate_license.js \
 *     --businessId <uuid> \
 *     --tier professional \
 *     --days 365 \
 *     [--deviceFingerprint <string>]
 *
 * The GASTROCORE_PRIVATE_SEED env var must be the 64-hex-char (32-byte)
 * Ed25519 private seed that corresponds to the public key embedded in
 * the app. Keep it secret — store it in your CI secrets or a vault.
 *
 * Example (dry-run with test seed — DO NOT use in production):
 *   GASTROCORE_PRIVATE_SEED=f22dec18eda312b73a7f5b3dd48f49d3802e390c2c81c765391d8545906b44fc \
 *     node generate_license.js \
 *     --businessId 550e8400-e29b-41d4-a716-446655440000 \
 *     --tier professional \
 *     --days 365
 */

'use strict';

const { createPrivateKey, sign } = require('crypto');
const { randomUUID } = require('crypto');

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

function parseArgs() {
  const args = process.argv.slice(2);
  const result = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) {
      result[args[i].slice(2)] = args[i + 1];
      i++;
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Key loading
// ---------------------------------------------------------------------------

/** Converts a raw 32-byte Ed25519 seed to a Node.js KeyObject via PKCS8 DER. */
function loadPrivateKey(seedHex) {
  if (!seedHex || seedHex.length !== 64) {
    throw new Error(
      'GASTROCORE_PRIVATE_SEED must be a 64-character hex string (32 bytes).'
    );
  }
  const seed = Buffer.from(seedHex, 'hex');
  // PKCS8 DER header for Ed25519 (RFC 8410):
  // SEQUENCE { INTEGER 0, SEQUENCE { OID 1.3.101.112 }, OCTET STRING { OCTET STRING { seed } } }
  const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
  const pkcs8Der = Buffer.concat([pkcs8Header, seed]);
  return createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
}

// ---------------------------------------------------------------------------
// Token construction
// ---------------------------------------------------------------------------

/**
 * Builds and signs a GastroCore license token.
 *
 * @param {object} opts
 * @param {CryptoKey} opts.privateKey  - Node.js KeyObject for signing
 * @param {string}    opts.businessId  - Customer UUID
 * @param {string}    opts.tier        - "free" | "professional" | "enterprise"
 * @param {number}    opts.validDays   - Token lifetime in days from now
 * @param {string}    [opts.deviceFingerprint] - Optional device lock string
 * @returns {string} Base64url-encoded token
 */
function generateToken({ privateKey, businessId, tier, validDays, deviceFingerprint }) {
  const now = new Date();
  const expires = new Date(now.getTime() + validDays * 24 * 60 * 60 * 1000);

  const payload = {
    v: 1,
    businessId,
    tier,
    issuedAt: now.toISOString(),
    expiresAt: expires.toISOString(),
  };
  if (deviceFingerprint) {
    payload.deviceFingerprint = deviceFingerprint;
  }

  // Canonical message: keys sorted, no whitespace.
  const sorted = Object.fromEntries(
    Object.entries(payload).sort(([a], [b]) => a.localeCompare(b))
  );
  const message = Buffer.from(JSON.stringify(sorted), 'utf8');

  // Ed25519 sign (deterministic, no hash pre-processing needed — Node passes
  // message directly to the Ed25519 primitive, matching RFC 8032).
  const sigBytes = sign(null, message, privateKey);
  const sigB64 = sigBytes.toString('base64url');

  // Final token = Base64url of the full JSON (payload + sig).
  const tokenJson = JSON.stringify({ ...payload, sig: sigB64 });
  return Buffer.from(tokenJson, 'utf8').toString('base64url');
}

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------

const VALID_TIERS = ['free', 'professional', 'enterprise'];

function validateTier(tier) {
  if (!VALID_TIERS.includes(tier)) {
    throw new Error(`--tier must be one of: ${VALID_TIERS.join(', ')}`);
  }
}

function validateUuid(id) {
  const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuidRe.test(id)) {
    throw new Error(`--businessId must be a valid UUID (got: ${id})`);
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main() {
  const args = parseArgs();
  const seedHex = process.env.GASTROCORE_PRIVATE_SEED;

  // Defaults
  const businessId = args.businessId ?? randomUUID();
  const tier = args.tier ?? 'professional';
  const validDays = parseInt(args.days ?? '365', 10);
  const deviceFingerprint = args.deviceFingerprint;

  // Validate
  if (!seedHex) {
    console.error('ERROR: Set GASTROCORE_PRIVATE_SEED=<hex> in the environment.');
    process.exit(1);
  }
  validateTier(tier);
  validateUuid(businessId);
  if (isNaN(validDays) || validDays < 1) {
    console.error('ERROR: --days must be a positive integer.');
    process.exit(1);
  }

  const privateKey = loadPrivateKey(seedHex);
  const token = generateToken({ privateKey, businessId, tier, validDays, deviceFingerprint });

  const expiresAt = new Date(Date.now() + validDays * 24 * 60 * 60 * 1000);

  console.log('');
  console.log('=== GastroCore License Token ===');
  console.log('');
  console.log('Business ID :', businessId);
  console.log('Tier        :', tier);
  console.log('Valid days  :', validDays);
  console.log('Expires     :', expiresAt.toISOString());
  if (deviceFingerprint) {
    console.log('Device lock :', deviceFingerprint);
  }
  console.log('');
  console.log('TOKEN (paste into POS settings):');
  console.log(token);
  console.log('');
}

main();
