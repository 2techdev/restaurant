package response

import (
	"encoding/json"
	"log/slog"
	"net/http"
)

// JSON writes a JSON response with the given status code and data.
func JSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if data != nil {
		if err := json.NewEncoder(w).Encode(data); err != nil {
			slog.Error("failed to encode response", "error", err)
		}
	}
}

// apiError is the standard error envelope.
type apiError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Details any    `json:"details,omitempty"`
}

// Error writes a JSON error response.
func Error(w http.ResponseWriter, status int, code string, message string) {
	JSON(w, status, apiError{
		Code:    code,
		Message: message,
	})
}

// ErrorWithDetails writes a JSON error response with additional details.
func ErrorWithDetails(w http.ResponseWriter, status int, code string, message string, details any) {
	JSON(w, status, apiError{
		Code:    code,
		Message: message,
		Details: details,
	})
}

// paginatedResponse is the standard paginated response envelope.
type paginatedResponse struct {
	Data    any    `json:"data"`
	Cursor  string `json:"cursor,omitempty"`
	HasMore bool   `json:"has_more"`
}

// Paginated writes a JSON paginated response.
func Paginated(w http.ResponseWriter, data any, cursor string, hasMore bool) {
	JSON(w, http.StatusOK, paginatedResponse{
		Data:    data,
		Cursor:  cursor,
		HasMore: hasMore,
	})
}

// Created writes a 201 Created JSON response.
func Created(w http.ResponseWriter, data any) {
	JSON(w, http.StatusCreated, data)
}

// NoContent writes a 204 No Content response.
func NoContent(w http.ResponseWriter) {
	w.WriteHeader(http.StatusNoContent)
}
