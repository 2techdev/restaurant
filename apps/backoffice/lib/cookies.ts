/**
 * Cookie name constants — middleware ve route handler'larda paylaşılır.
 * Bu dosya hiçbir runtime-sensitive modül import etmez (next/headers vs.).
 */
export const COOKIE_TOKEN = "bo_token";
export const COOKIE_REFRESH = "bo_refresh";
export const COOKIE_USER = "bo_user";
export const COOKIE_TENANT = "bo_tenant";

// Super admin impersonation (F1, migration 024). While impersonating, *_ORIG
// cookies hold the super admin's own session. Active session cookies are
// swapped with the impersonation JWT + target user. Exit restores from *_ORIG.
export const COOKIE_TOKEN_ORIG = "bo_token_orig";
export const COOKIE_USER_ORIG = "bo_user_orig";
export const COOKIE_TENANT_ORIG = "bo_tenant_orig";
