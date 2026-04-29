/**
 * Cookie name constants — middleware ve route handler'larda paylaşılır.
 * Bu dosya hiçbir runtime-sensitive modül import etmez (next/headers vs.).
 */
export const COOKIE_TOKEN = "bo_token";
export const COOKIE_REFRESH = "bo_refresh";
export const COOKIE_USER = "bo_user";
export const COOKIE_TENANT = "bo_tenant";
