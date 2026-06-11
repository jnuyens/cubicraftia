// Package hub — blocks.go
// Server-side enforcement for the block relationship.
// The signaling server is the hard gate: a modified client cannot bypass a block.
// All queries use the Supabase service-role key (bypasses RLS) so mutual-block
// enforcement sees rows in both directions.
package hub

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

// isBlockedBetween returns true if either uidA has blocked uidB or uidB has blocked uidA.
// It queries the Supabase PostgREST /rest/v1/blocks endpoint with a bidirectional OR
// filter and returns as soon as any row is found (limit=1).
//
// Error semantics: on any network or Supabase error, the function returns (false, err).
// Callers should fail closed (reject the join) when err != nil.
func (h *Hub) isBlockedBetween(uidA, uidB string) (bool, error) {
	if h.cfg.SupabaseURL == "" {
		return false, nil // no Supabase configured — allow (dev mode)
	}

	// PostgREST OR filter for both block directions.
	// Syntax: ?or=(and(blocker_uid.eq.A,blocked_uid.eq.B),and(blocker_uid.eq.B,blocked_uid.eq.A))
	filter := fmt.Sprintf(
		"or=(and(blocker_uid.eq.%s,blocked_uid.eq.%s),and(blocker_uid.eq.%s,blocked_uid.eq.%s))",
		url.QueryEscape(uidA),
		url.QueryEscape(uidB),
		url.QueryEscape(uidB),
		url.QueryEscape(uidA),
	)
	endpoint := fmt.Sprintf("%s/rest/v1/blocks?%s&select=blocker_uid&limit=1", h.cfg.SupabaseURL, filter)

	req, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		return false, fmt.Errorf("isBlockedBetween: build request: %w", err)
	}
	req.Header.Set("apikey", h.cfg.SupabaseServiceKey)
	req.Header.Set("Authorization", "Bearer "+h.cfg.SupabaseServiceKey)

	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return false, fmt.Errorf("isBlockedBetween: HTTP: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return false, fmt.Errorf("isBlockedBetween: Supabase returned %d: %s", resp.StatusCode, body)
	}

	var rows []json.RawMessage
	if err := json.NewDecoder(resp.Body).Decode(&rows); err != nil {
		return false, fmt.Errorf("isBlockedBetween: decode: %w", err)
	}
	return len(rows) > 0, nil
}

// isConsentRequired returns true when the given uid belongs to a child account
// (parental_consents row exists) AND the parent has not yet confirmed (consented_at IS NULL).
//
// If no row exists in parental_consents for this uid, the account is not marked as
// under-13, so consent is not required (returns false).
func (h *Hub) isConsentRequired(uid string) (bool, error) {
	if h.cfg.SupabaseURL == "" {
		return false, nil // dev mode
	}

	endpoint := fmt.Sprintf(
		"%s/rest/v1/parental_consents?child_uid=eq.%s&select=consented_at,revoked_at&limit=1",
		h.cfg.SupabaseURL,
		url.QueryEscape(uid),
	)

	req, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		return false, fmt.Errorf("isConsentRequired: build request: %w", err)
	}
	req.Header.Set("apikey", h.cfg.SupabaseServiceKey)
	req.Header.Set("Authorization", "Bearer "+h.cfg.SupabaseServiceKey)

	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return false, fmt.Errorf("isConsentRequired: HTTP: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return false, fmt.Errorf("isConsentRequired: Supabase returned %d: %s", resp.StatusCode, body)
	}

	var rows []struct {
		ConsentedAt *string `json:"consented_at"`
		RevokedAt   *string `json:"revoked_at"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&rows); err != nil {
		return false, fmt.Errorf("isConsentRequired: decode: %w", err)
	}
	if len(rows) == 0 {
		// No parental_consents row — account is not flagged under-13.
		return false, nil
	}
	row := rows[0]
	// Consent is required if: row exists AND (consented_at is nil OR consent was revoked).
	if row.ConsentedAt == nil || (row.RevokedAt != nil && *row.RevokedAt != "") {
		return true, nil
	}
	return false, nil
}

// checkReportRateLimit returns true if the reporter is allowed to submit another report
// (fewer than 5 reports in the last 24 hours), or false if they are rate-limited.
// Enforcement: T-05-D1 — deny-of-service via mass-report flood.
func (h *Hub) checkReportRateLimit(reporterUID string) (bool, error) {
	if h.cfg.SupabaseURL == "" {
		return true, nil // dev mode — allow
	}

	since := time.Now().Add(-24 * time.Hour).Format(time.RFC3339)
	endpoint := fmt.Sprintf(
		"%s/rest/v1/reports?reporter_uid=eq.%s&created_at=gte.%s&select=id&limit=6",
		h.cfg.SupabaseURL,
		url.QueryEscape(reporterUID),
		url.QueryEscape(since),
	)

	req, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		return false, fmt.Errorf("checkReportRateLimit: build request: %w", err)
	}
	req.Header.Set("apikey", h.cfg.SupabaseServiceKey)
	req.Header.Set("Authorization", "Bearer "+h.cfg.SupabaseServiceKey)

	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return false, fmt.Errorf("checkReportRateLimit: HTTP: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return false, fmt.Errorf("checkReportRateLimit: Supabase returned %d: %s", resp.StatusCode, body)
	}

	var rows []json.RawMessage
	if err := json.NewDecoder(resp.Body).Decode(&rows); err != nil {
		return false, fmt.Errorf("checkReportRateLimit: decode: %w", err)
	}
	// Rate-limited if already at or above 5 reports.
	return len(rows) < 5, nil
}
