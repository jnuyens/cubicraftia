// Package hub — consent.go
// Parental consent lifecycle endpoints for under-13 (COPPA 2025) accounts.
//
// Three HTTP handlers:
//   - POST /consent/request  (authenticated) — generates tokens, writes parental_consents, sends SMTP email
//   - GET  /consent/confirm?token= (public)  — validates token, sets consented_at, clears token (single-use)
//   - GET  /consent/revoke?token=  (public)  — sets revoked_at
//
// Security notes:
//   - Tokens are 128-bit random values (crypto/rand) base32-encoded — brute-force infeasible (T-05-S1).
//   - confirm token is cleared (set to NULL) after first use — single-use property.
//   - Expiry: 7 days from requested_at; HandleConfirm rejects expired tokens.
//   - SMTP is used directly (net/smtp); GoTrue email templates are NOT used (Pitfall 3).
package hub

import (
	"bytes"
	"crypto/rand"
	"encoding/base32"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/smtp"
	"net/url"
	"strings"
	"time"
)

// ConsentHandler exposes the parental consent HTTP handlers.
type ConsentHandler struct {
	hub *Hub
}

// NewConsentHandler creates a ConsentHandler backed by the given Hub.
func NewConsentHandler(h *Hub) *ConsentHandler {
	return &ConsentHandler{hub: h}
}

// consentEmailTemplate is the HTML email body sent to the parent.
// Placeholders: {{child_username}}, {{confirm_link}}, {{revoke_link}}.
const consentEmailTemplate = `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Parental Consent — Cubicraftia</title></head>
<body style="font-family:sans-serif;max-width:600px;margin:0 auto;padding:24px">
  <h1 style="color:#2d6be4">Cubicraftia Parental Consent</h1>
  <p>Your child <strong>{{child_username}}</strong> has created an account on Cubicraftia,
  a brick-building sandbox game. Because they are under 13, we need your consent before
  they can join multiplayer sessions.</p>

  <p style="background:#f0f4ff;border-left:4px solid #2d6be4;padding:12px;margin:16px 0">
    <strong>By clicking Confirm below, I confirm that I am the parent or legal guardian
    of {{child_username}} on Cubicraftia and consent to their participation in online
    multiplayer sessions.</strong>
  </p>

  <p>
    <a href="{{confirm_link}}"
       style="display:inline-block;background:#2d6be4;color:#fff;padding:12px 24px;
              border-radius:4px;text-decoration:none;font-weight:bold">
      Confirm Parental Consent
    </a>
  </p>

  <p>If you did not request this or do not consent, you can ignore this email or
  <a href="{{revoke_link}}">revoke access here</a>.</p>

  <p style="font-size:12px;color:#666">
    This link expires in 7 days. Cubicraftia is not affiliated with LEGO or Minecraft.
    Questions? Contact us at support@cubicraftia.example.
  </p>
</body>
</html>`

// consentEmailPlainText is the plain-text fallback.
const consentEmailPlainText = `Cubicraftia Parental Consent

Your child {{child_username}} has created an account on Cubicraftia,
a brick-building sandbox game. Because they are under 13, we need your
consent before they can join multiplayer sessions.

By clicking Confirm below, I confirm that I am the parent or legal guardian
of {{child_username}} on Cubicraftia and consent to their participation in
online multiplayer sessions.

Confirm parental consent:
{{confirm_link}}

Revoke access:
{{revoke_link}}

This link expires in 7 days.
`

// generateToken generates a 128-bit (16-byte) cryptographically random token
// and encodes it as base32 without padding (26 characters).
func generateToken() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", fmt.Errorf("generateToken: %w", err)
	}
	return base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(b[:]), nil
}

// HandleRequest handles POST /consent/request.
// The child must be authenticated (JWT required). The body must contain parent_email.
// On success, inserts a parental_consents row and sends an SMTP email to the parent.
func (ch *ConsentHandler) HandleRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Authenticate the child.
	tokenStr := ""
	if auth := r.Header.Get("Authorization"); strings.HasPrefix(auth, "Bearer ") {
		tokenStr = strings.TrimPrefix(auth, "Bearer ")
	}
	childUID, err := VerifyJWT(tokenStr, ch.hub.cfg.JWTSecret)
	if err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Decode request body.
	var body struct {
		ParentEmail   string `json:"parent_email"`
		ChildUsername string `json:"child_username"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 4096)).Decode(&body); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	if body.ParentEmail == "" {
		http.Error(w, `{"error":"missing parent_email"}`, http.StatusBadRequest)
		return
	}
	// CR-02: Reject CRLF/NUL in parent_email to prevent MIME header injection.
	if strings.ContainsAny(body.ParentEmail, "\r\n\x00") {
		http.Error(w, `{"error":"invalid_parent_email"}`, http.StatusBadRequest)
		return
	}
	// Basic format validation: must contain @ and be within RFC 5321 limit.
	if !strings.Contains(body.ParentEmail, "@") || len(body.ParentEmail) > 254 {
		http.Error(w, `{"error":"invalid_parent_email"}`, http.StatusBadRequest)
		return
	}
	if body.ChildUsername == "" {
		body.ChildUsername = childUID // fallback to UID if no username provided
	}

	// Generate tokens.
	consentToken, err := generateToken()
	if err != nil {
		log.Printf("[consent] token generation error: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	revokeToken, err := generateToken()
	if err != nil {
		log.Printf("[consent] revoke token generation error: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	// INSERT parental_consents row via Supabase service role.
	insertBody := map[string]interface{}{
		"child_uid":     childUID,
		"parent_email":  body.ParentEmail,
		"consent_token": consentToken,
		"revoke_token":  revokeToken,
	}
	insertBytes, _ := json.Marshal(insertBody)

	endpoint := ch.hub.cfg.SupabaseURL + "/rest/v1/parental_consents"
	req, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(insertBytes))
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	req.Header.Set("apikey", ch.hub.cfg.SupabaseServiceKey)
	req.Header.Set("Authorization", "Bearer "+ch.hub.cfg.SupabaseServiceKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")

	httpClient := &http.Client{Timeout: 5 * time.Second}
	resp, err := httpClient.Do(req)
	if err != nil {
		log.Printf("[consent] Supabase insert error: %v", err)
		http.Error(w, "upstream error", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusConflict {
		// Row already exists — consent already requested.
		http.Error(w, `{"error":"consent_already_requested"}`, http.StatusConflict)
		return
	}
	if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		log.Printf("[consent] Supabase insert returned %d: %s", resp.StatusCode, respBody)
		http.Error(w, "upstream error", http.StatusBadGateway)
		return
	}

	// Send SMTP email to parent.
	confirmLink := fmt.Sprintf("https://%s/consent/confirm?token=%s", ch.hub.cfg.ConsentBaseURL, consentToken)
	revokeLink := fmt.Sprintf("https://%s/consent/revoke?token=%s", ch.hub.cfg.ConsentBaseURL, revokeToken)

	if err := ch.sendConsentEmail(body.ParentEmail, body.ChildUsername, confirmLink, revokeLink); err != nil {
		// Log but do not fail the request — the DB row is created; email can be retried.
		log.Printf("[consent] SMTP error sending to %s: %v", body.ParentEmail, err)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, `{"status":"consent_email_sent"}`)
}

// HandleConfirm handles GET /consent/confirm?token=...
// Validates the consent token, sets consented_at, clears the consent token (single-use),
// and updates GoTrue user metadata. Returns an HTML page.
func (ch *ConsentHandler) HandleConfirm(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	if token == "" {
		http.Error(w, "missing token", http.StatusBadRequest)
		return
	}

	// Look up the token — must be unused (consented_at IS NULL) and not expired.
	row, err := ch.fetchConsentRow("consent_token", token)
	if err != nil {
		log.Printf("[consent] HandleConfirm fetch error: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	if row == nil {
		http.Error(w, "token not found or already used", http.StatusNotFound)
		return
	}
	if row.ConsentedAt != nil {
		// Already confirmed.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprintln(w, "<html><body><h1>Parental consent already confirmed.</h1></body></html>")
		return
	}
	// Check expiry: 7 days from requested_at.
	if time.Since(row.RequestedAt) > 7*24*time.Hour {
		http.Error(w, "token expired", http.StatusGone)
		return
	}

	// PATCH: set consented_at = NOW(), clear consent_token (single-use), clear
	// revoked_at so that re-consent after revocation is correctly recognised by
	// isConsentRequired (CR-05).
	now := time.Now().UTC().Format(time.RFC3339)
	patchBody := map[string]interface{}{
		"consented_at":  now,
		"consent_token": nil, // clear — single-use
		"revoked_at":    nil, // clear revocation on re-consent
	}
	if err := ch.patchConsentRow(row.ChildUID, patchBody); err != nil {
		log.Printf("[consent] HandleConfirm patch error: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	// Update GoTrue user metadata.
	if err := ch.patchGoTrueUserMeta(row.ChildUID, map[string]interface{}{"consented_at": now}); err != nil {
		log.Printf("[consent] HandleConfirm GoTrue patch error: %v", err)
		// Non-fatal: consent row is already set.
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprintln(w, `<html><body><h1>Parental consent confirmed.</h1>
<p>Your child can now join multiplayer sessions on Cubicraftia. Thank you!</p>
</body></html>`)
}

// HandleRevoke handles GET /consent/revoke?token=...
// Sets revoked_at and clears GoTrue consented_at metadata. Returns an HTML page.
func (ch *ConsentHandler) HandleRevoke(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	if token == "" {
		http.Error(w, "missing token", http.StatusBadRequest)
		return
	}

	row, err := ch.fetchConsentRow("revoke_token", token)
	if err != nil {
		log.Printf("[consent] HandleRevoke fetch error: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	if row == nil {
		http.Error(w, "token not found", http.StatusNotFound)
		return
	}
	if row.RevokedAt != nil {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprintln(w, "<html><body><h1>Parental consent already revoked.</h1></body></html>")
		return
	}

	now := time.Now().UTC().Format(time.RFC3339)
	patchBody := map[string]interface{}{
		"revoked_at": now,
	}
	if err := ch.patchConsentRow(row.ChildUID, patchBody); err != nil {
		log.Printf("[consent] HandleRevoke patch error: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	// Clear GoTrue consented_at.
	if err := ch.patchGoTrueUserMeta(row.ChildUID, map[string]interface{}{"consented_at": nil}); err != nil {
		log.Printf("[consent] HandleRevoke GoTrue patch error: %v", err)
		// Non-fatal.
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprintln(w, `<html><body><h1>Parental consent revoked.</h1>
<p>Your child's multiplayer access on Cubicraftia has been removed.</p>
</body></html>`)
}

// consentRow is the subset of parental_consents columns we need.
type consentRow struct {
	ChildUID    string     `json:"child_uid"`
	RequestedAt time.Time  `json:"requested_at"`
	ConsentedAt *string    `json:"consented_at"`
	RevokedAt   *string    `json:"revoked_at"`
}

// fetchConsentRow queries Supabase for a row by tokenField (either "consent_token" or "revoke_token").
// Returns nil if no row found.
func (ch *ConsentHandler) fetchConsentRow(tokenField, token string) (*consentRow, error) {
	// CR-07: percent-encode both tokenField and token to prevent URL injection.
	endpoint := fmt.Sprintf(
		"%s/rest/v1/parental_consents?%s=eq.%s&select=child_uid,requested_at,consented_at,revoked_at&limit=1",
		ch.hub.cfg.SupabaseURL,
		url.QueryEscape(tokenField),
		url.QueryEscape(token),
	)
	req, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("apikey", ch.hub.cfg.SupabaseServiceKey)
	req.Header.Set("Authorization", "Bearer "+ch.hub.cfg.SupabaseServiceKey)

	httpClient := &http.Client{Timeout: 5 * time.Second}
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return nil, fmt.Errorf("Supabase returned %d: %s", resp.StatusCode, body)
	}

	var rows []consentRow
	if err := json.NewDecoder(resp.Body).Decode(&rows); err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, nil
	}
	return &rows[0], nil
}

// patchConsentRow sends a PATCH to the parental_consents row for childUID.
func (ch *ConsentHandler) patchConsentRow(childUID string, fields map[string]interface{}) error {
	bodyBytes, _ := json.Marshal(fields)
	endpoint := fmt.Sprintf(
		"%s/rest/v1/parental_consents?child_uid=eq.%s",
		ch.hub.cfg.SupabaseURL,
		childUID,
	)
	req, err := http.NewRequest(http.MethodPatch, endpoint, bytes.NewReader(bodyBytes))
	if err != nil {
		return err
	}
	req.Header.Set("apikey", ch.hub.cfg.SupabaseServiceKey)
	req.Header.Set("Authorization", "Bearer "+ch.hub.cfg.SupabaseServiceKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")

	httpClient := &http.Client{Timeout: 5 * time.Second}
	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return fmt.Errorf("PATCH returned %d: %s", resp.StatusCode, body)
	}
	return nil
}

// patchGoTrueUserMeta calls the Supabase admin API to update a user's user_metadata.
// Used to reflect consented_at / revoked state in the JWT claims.
func (ch *ConsentHandler) patchGoTrueUserMeta(uid string, meta map[string]interface{}) error {
	bodyBytes, _ := json.Marshal(map[string]interface{}{"user_metadata": meta})
	endpoint := fmt.Sprintf("%s/auth/v1/admin/users/%s", ch.hub.cfg.SupabaseURL, uid)

	req, err := http.NewRequest(http.MethodPatch, endpoint, bytes.NewReader(bodyBytes))
	if err != nil {
		return err
	}
	req.Header.Set("apikey", ch.hub.cfg.SupabaseServiceKey)
	req.Header.Set("Authorization", "Bearer "+ch.hub.cfg.SupabaseServiceKey)
	req.Header.Set("Content-Type", "application/json")

	httpClient := &http.Client{Timeout: 5 * time.Second}
	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return fmt.Errorf("GoTrue PATCH returned %d: %s", resp.StatusCode, body)
	}
	return nil
}

// sendConsentEmail sends the parental consent email via net/smtp.
// Builds a multipart MIME message with HTML and plain-text parts.
func (ch *ConsentHandler) sendConsentEmail(to, childUsername, confirmLink, revokeLink string) error {
	cfg := ch.hub.cfg
	if cfg.SMTPHost == "" {
		log.Printf("[consent] SMTP not configured — skipping email to %s", to)
		return nil
	}

	htmlBody := strings.NewReplacer(
		"{{child_username}}", childUsername,
		"{{confirm_link}}", confirmLink,
		"{{revoke_link}}", revokeLink,
	).Replace(consentEmailTemplate)

	textBody := strings.NewReplacer(
		"{{child_username}}", childUsername,
		"{{confirm_link}}", confirmLink,
		"{{revoke_link}}", revokeLink,
	).Replace(consentEmailPlainText)

	boundary := "cubicraftia-consent-20260101"
	var msg strings.Builder
	msg.WriteString("From: " + cfg.SMTPFrom + "\r\n")
	msg.WriteString("To: " + to + "\r\n")
	msg.WriteString("Subject: Parental Consent Required — Cubicraftia\r\n")
	msg.WriteString("MIME-Version: 1.0\r\n")
	msg.WriteString(`Content-Type: multipart/alternative; boundary="` + boundary + `"` + "\r\n")
	msg.WriteString("\r\n")

	// Plain text part.
	msg.WriteString("--" + boundary + "\r\n")
	msg.WriteString("Content-Type: text/plain; charset=utf-8\r\n")
	msg.WriteString("Content-Transfer-Encoding: 7bit\r\n")
	msg.WriteString("\r\n")
	msg.WriteString(textBody)
	msg.WriteString("\r\n")

	// HTML part.
	msg.WriteString("--" + boundary + "\r\n")
	msg.WriteString("Content-Type: text/html; charset=utf-8\r\n")
	msg.WriteString("Content-Transfer-Encoding: 7bit\r\n")
	msg.WriteString("\r\n")
	msg.WriteString(htmlBody)
	msg.WriteString("\r\n")

	msg.WriteString("--" + boundary + "--\r\n")

	addr := fmt.Sprintf("%s:%d", cfg.SMTPHost, cfg.SMTPPort)
	var auth smtp.Auth
	if cfg.SMTPUser != "" {
		auth = smtp.PlainAuth("", cfg.SMTPUser, cfg.SMTPPassword, cfg.SMTPHost)
	}

	return smtp.SendMail(addr, auth, cfg.SMTPFrom, []string{to}, []byte(msg.String()))
}
