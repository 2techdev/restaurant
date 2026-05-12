/** Cookie names — middleware + route handlers share these. No runtime
 *  imports so this stays edge-safe. Different prefix (pp_) from backoffice
 *  (bo_) so a browser logged into both never confuses sessions. */
export const COOKIE_TOKEN = "pp_token";
export const COOKIE_USER = "pp_user";
