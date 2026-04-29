package org

import (
	"context"
	"database/sql"
	"errors"
	"net/http"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

// userOrgInfo is the minimum identity needed for HQ authorization.
type userOrgInfo struct {
	UserID         string
	OrganizationID string
	OrgRole        string
}

// resolveUser pulls the user's organization_id and org_role from the JWT
// claims first (stamped at admin/user login by mapAdminRoleToOrgRole), and
// falls back to a DB lookup against users/admin_users when the JWT does not
// carry HQ fields (legacy tokens issued before 014_hq_chain).
//
// Lookup order:
//   1. JWT claims:   organization_id + org_role
//   2. users table:  for native HQ users created post-014
//   3. admin_users:  for legacy backoffice operators — admin_users.role is
//                    mapped to the HQ taxonomy via mapAdminRoleAtDB.
//   4. JWT role:     last-resort fallback for raw role claims.
func (m *Module) resolveUser(ctx context.Context) (userOrgInfo, error) {
	uid := middleware.GetUserID(ctx)
	if !uuid.IsValid(uid) {
		return userOrgInfo{}, errors.New("missing user_id")
	}

	info := userOrgInfo{UserID: uid}

	// 1) Prefer JWT — set at login.
	if jwtOrgID := middleware.GetOrganizationID(ctx); jwtOrgID != "" {
		info.OrganizationID = jwtOrgID
	}
	if jwtOrgRole := middleware.GetOrgRole(ctx); jwtOrgRole != "" {
		info.OrgRole = jwtOrgRole
	}
	if info.OrganizationID != "" && info.OrgRole != "" {
		return info, nil
	}

	// 2) Fallback to users table (HQ-native users post-014).
	var orgID, orgRole sql.NullString
	err := m.db.QueryRowContext(ctx, `
		SELECT organization_id::text, org_role
		FROM users WHERE id = $1
	`, uid).Scan(&orgID, &orgRole)
	if err == nil {
		if orgID.Valid && info.OrganizationID == "" {
			info.OrganizationID = orgID.String
		}
		if orgRole.Valid && info.OrgRole == "" {
			info.OrgRole = orgRole.String
		}
	} else if err != sql.ErrNoRows {
		return userOrgInfo{}, err
	}

	// 3) Fallback to admin_users (legacy backoffice operators).
	if info.OrganizationID == "" || info.OrgRole == "" {
		var adminOrgID, adminRole sql.NullString
		err := m.db.QueryRowContext(ctx, `
			SELECT organization_id::text, role
			FROM admin_users WHERE id = $1
		`, uid).Scan(&adminOrgID, &adminRole)
		if err == nil {
			if adminOrgID.Valid && info.OrganizationID == "" {
				info.OrganizationID = adminOrgID.String
			}
			if adminRole.Valid && info.OrgRole == "" {
				info.OrgRole = mapAdminRoleAtDB(adminRole.String)
			}
		} else if err != sql.ErrNoRows {
			return userOrgInfo{}, err
		}
	}

	// 4) Last resort: legacy raw JWT role claim.
	if info.OrgRole == "" {
		info.OrgRole = middleware.GetRole(ctx)
	}

	return info, nil
}

// mapAdminRoleAtDB mirrors auth.mapAdminRoleToOrgRole — duplicated here so the
// org package does not import auth (would be an import cycle).
func mapAdminRoleAtDB(adminRole string) string {
	switch adminRole {
	case "admin":
		return RoleHQAdmin
	case "brand_manager":
		return RoleHQManager
	case "store_manager":
		return RoleRestaurantManager
	default:
		return ""
	}
}

// authorize enforces:
//   1. user has a known organization
//   2. orgID in URL matches user's org (unless the user is a master admin
//      with a NULL organization_id — reserved for system/superadmin flows)
//   3. role is in the allowed set (empty allowed means "any HQ role")
func (m *Module) authorize(w http.ResponseWriter, r *http.Request, orgID string, allowed ...string) (userOrgInfo, bool) {
	if !uuid.IsValid(orgID) {
		response.Error(w, http.StatusBadRequest, "INVALID_ORG_ID", "Invalid organization id")
		return userOrgInfo{}, false
	}
	info, err := m.resolveUser(r.Context())
	if err != nil {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "User context required")
		return userOrgInfo{}, false
	}
	if info.OrganizationID != "" && info.OrganizationID != orgID {
		response.Error(w, http.StatusForbidden, "ORG_MISMATCH", "User does not belong to this organization")
		return userOrgInfo{}, false
	}
	if info.OrganizationID == "" {
		// Not assigned to any org — accept only if JWT role indicates HQ admin.
		// This lets an org be bootstrapped by a privileged operator.
		if info.OrgRole != RoleHQAdmin {
			response.Error(w, http.StatusForbidden, "NO_ORG", "User is not bound to an organization")
			return userOrgInfo{}, false
		}
		info.OrganizationID = orgID
	}
	if len(allowed) > 0 {
		ok := false
		for _, a := range allowed {
			if a == info.OrgRole {
				ok = true
				break
			}
		}
		if !ok {
			response.Error(w, http.StatusForbidden, "FORBIDDEN", "Insufficient role for HQ action")
			return userOrgInfo{}, false
		}
	}
	return info, true
}

// hqOnly is a convenience: HQ_ADMIN or HQ_MANAGER.
func (m *Module) hqOnly(w http.ResponseWriter, r *http.Request, orgID string) (userOrgInfo, bool) {
	return m.authorize(w, r, orgID, RoleHQAdmin, RoleHQManager)
}

// hqAdminOnly is a convenience: HQ_ADMIN only (for destructive ops).
func (m *Module) hqAdminOnly(w http.ResponseWriter, r *http.Request, orgID string) (userOrgInfo, bool) {
	return m.authorize(w, r, orgID, RoleHQAdmin)
}
