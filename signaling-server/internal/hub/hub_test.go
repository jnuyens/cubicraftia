package hub

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/cubicraftia/signaling-server/internal/config"
)

// --- Helper: build a valid HS256 JWT for testing ---

func buildTestJWT(secret string, sub string, expOffset time.Duration) string {
	header := base64.RawURLEncoding.EncodeToString([]byte(`{"alg":"HS256","typ":"JWT"}`))
	expTime := time.Now().Add(expOffset).Unix()
	payloadJSON := fmt.Sprintf(`{"sub":"%s","exp":%d}`, sub, expTime)
	payload := base64.RawURLEncoding.EncodeToString([]byte(payloadJSON))
	signingInput := header + "." + payload
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(signingInput))
	sig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	return signingInput + "." + sig
}

// --- SessionRegistry unit tests ---

// TestSessionRegisterAndGet verifies basic register + get semantics.
func TestSessionRegisterAndGet(t *testing.T) {
	reg := NewSessionRegistry(200)

	err := reg.Register("sess-001", "user-aaa", "My World", 4)
	if err != nil {
		t.Fatalf("Register failed unexpectedly: %v", err)
	}

	s := reg.Get("sess-001")
	if s == nil {
		t.Fatal("Get returned nil after Register")
	}
	if s.HostUID != "user-aaa" {
		t.Errorf("HostUID = %q, want %q", s.HostUID, "user-aaa")
	}
	if s.WorldName != "My World" {
		t.Errorf("WorldName = %q, want %q", s.WorldName, "My World")
	}
	if s.MaxPeers != 4 {
		t.Errorf("MaxPeers = %d, want 4", s.MaxPeers)
	}
	if s.PeerCount != 1 {
		t.Errorf("PeerCount = %d, want 1 (host)", s.PeerCount)
	}
	if s.PublishedAt.IsZero() {
		t.Error("PublishedAt must not be zero — required for session_list published_at_unix")
	}
}

// TestSessionCapacityWarning verifies that registering past the soft cap does not
// fail (it is a soft cap that logs a warning, not a hard block at Register).
func TestSessionCapacityWarning(t *testing.T) {
	reg := NewSessionRegistry(2) // low cap for testing

	for i := 0; i < 3; i++ {
		id := fmt.Sprintf("sess-%03d", i)
		if err := reg.Register(id, "user-x", "World", 4); err != nil {
			t.Fatalf("Register[%d] failed: %v", i, err)
		}
	}
	// All three sessions exist (soft cap is a warning, not a hard block).
	if reg.Get("sess-002") == nil {
		t.Error("3rd session should exist even past soft cap")
	}
}

// TestUpdateHost verifies that UpdateHost changes the HostUID correctly.
func TestUpdateHost(t *testing.T) {
	reg := NewSessionRegistry(200)
	if err := reg.Register("sess-upd", "old-host", "World", 4); err != nil {
		t.Fatal(err)
	}
	if err := reg.UpdateHost("sess-upd", "new-host"); err != nil {
		t.Fatalf("UpdateHost failed: %v", err)
	}
	s := reg.Get("sess-upd")
	if s.HostUID != "new-host" {
		t.Errorf("HostUID = %q, want %q", s.HostUID, "new-host")
	}
}

// TestUpdateHostNotFound verifies that UpdateHost returns an error for unknown sessions.
func TestUpdateHostNotFound(t *testing.T) {
	reg := NewSessionRegistry(200)
	if err := reg.UpdateHost("does-not-exist", "uid"); err == nil {
		t.Error("expected error for missing session, got nil")
	}
}

// TestPruneIdle verifies that PruneIdle removes sessions past the idle deadline.
func TestPruneIdle(t *testing.T) {
	reg := NewSessionRegistry(200)
	if err := reg.Register("old-sess", "uid", "World", 4); err != nil {
		t.Fatal(err)
	}
	// Manually back-date LastActivity.
	reg.mu.Lock()
	reg.sessions["old-sess"].LastActivity = time.Now().Add(-20 * time.Minute)
	reg.mu.Unlock()

	reg.PruneIdle(15 * time.Minute)

	if reg.Get("old-sess") != nil {
		t.Error("session should have been pruned after 20 min idle (timeout=15 min)")
	}
}

// TestPruneIdleKeepsActive verifies that active sessions are not pruned.
func TestPruneIdleKeepsActive(t *testing.T) {
	reg := NewSessionRegistry(200)
	if err := reg.Register("live-sess", "uid", "World", 4); err != nil {
		t.Fatal(err)
	}
	reg.PruneIdle(15 * time.Minute) // session was just registered — far from idle
	if reg.Get("live-sess") == nil {
		t.Error("recently active session should not be pruned")
	}
}

// TestSessionListEntry verifies that toListEntry exposes published_at_unix.
func TestSessionListEntry(t *testing.T) {
	reg := NewSessionRegistry(200)
	before := time.Now().Unix()
	if err := reg.Register("sess-list", "uid", "World", 4); err != nil {
		t.Fatal(err)
	}
	after := time.Now().Unix()

	s := reg.Get("sess-list")
	entry := s.toListEntry()
	if entry.PublishedAtUnix < before || entry.PublishedAtUnix > after {
		t.Errorf("PublishedAtUnix %d not in [%d, %d]", entry.PublishedAtUnix, before, after)
	}
	if entry.SessionID != "sess-list" {
		t.Errorf("SessionID = %q, want %q", entry.SessionID, "sess-list")
	}
}

// --- Security-critical tests ---

// TestJWTRejectionOnConnect verifies that HandleConn returns HTTP 401 when:
//   - no Authorization header is present (empty token)
//   - an invalid (garbage) token is presented
//
// Uses net/http/httptest so no real WebSocket server is needed.
func TestJWTRejectionOnConnect(t *testing.T) {
	cfg := &config.Config{
		Port:        8080,
		JWTSecret:   "test-secret-32-bytes-padded-here",
		MaxSessions: 200,
	}
	h := NewHub(cfg)

	cases := []struct {
		name   string
		header string
		query  string
	}{
		{"no token", "", ""},
		{"invalid token", "Bearer not.a.valid.token", ""},
		{"wrong secret", "Bearer " + buildTestJWT("wrong-secret", "uid-1", time.Hour), ""},
		{"expired token", "Bearer " + buildTestJWT(cfg.JWTSecret, "uid-1", -time.Hour), ""},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/ws", nil)
			if tc.header != "" {
				req.Header.Set("Authorization", tc.header)
			}
			if tc.query != "" {
				q := req.URL.Query()
				q.Set("token", tc.query)
				req.URL.RawQuery = q.Encode()
			}
			w := httptest.NewRecorder()
			h.HandleConn(w, req)

			resp := w.Result()
			if resp.StatusCode != http.StatusUnauthorized {
				t.Errorf("%s: got HTTP %d, want 401 Unauthorized", tc.name, resp.StatusCode)
			}
		})
	}
}

// TestFourPeerMaxEnforced verifies that:
//  1. SessionRegistry.Register rejects max_peers > 4 with an error.
//  2. Hub.handleMessage for publish_session with max_peers=5 sends back an error response.
func TestFourPeerMaxEnforced(t *testing.T) {
	// Part 1: SessionRegistry.Register rejects max_peers > 4.
	reg := NewSessionRegistry(200)
	err := reg.Register("sess-5peer", "uid", "World", 5)
	if err == nil {
		t.Error("expected error when max_peers=5, got nil")
	}

	// Part 2: Hub.handleMessage for publish_session with max_peers=5 returns error.
	cfg := &config.Config{
		Port:        8080,
		JWTSecret:   "test-secret",
		MaxSessions: 200,
	}
	h := NewHub(cfg)

	client := &Client{
		uid:  "test-uid",
		send: make(chan []byte, sendBufferSize),
	}

	payload := map[string]interface{}{
		"session_id": "sess-bad",
		"world_name": "Test World",
		"max_peers":  5,
	}
	payloadBytes, _ := json.Marshal(payload)
	rawMsg := map[string]interface{}{
		"v":       1,
		"type":    "publish_session",
		"payload": json.RawMessage(payloadBytes),
	}
	rawBytes, _ := json.Marshal(rawMsg)

	h.handleMessage(client, rawBytes)

	select {
	case msg := <-client.send:
		var env envelope
		if err := json.Unmarshal(msg, &env); err != nil {
			t.Fatalf("response is not valid JSON: %v", err)
		}
		if env.Type != "error" {
			t.Errorf("response type = %q, want %q", env.Type, "error")
		}
		// Verify the error payload contains a recognisable code.
		var errPayload struct {
			Code string `json:"code"`
		}
		if err := json.Unmarshal(env.Payload, &errPayload); err != nil {
			t.Fatalf("error payload not parseable: %v", err)
		}
		if !strings.Contains(errPayload.Code, "peer_limit") && !strings.Contains(errPayload.Code, "limit") {
			t.Errorf("error code = %q, want something containing 'peer_limit'", errPayload.Code)
		}
	default:
		t.Error("expected an error response in client.send, got nothing")
	}
}

// TestTURNCredentials verifies that GenerateTURNCredentials produces non-empty credentials
// and that the username encodes the session ID and TTL.
func TestTURNCredentials(t *testing.T) {
	creds := GenerateTURNCredentials("my-session-id", "shared-secret", 3600)
	if creds.Username == "" {
		t.Error("TURN username must not be empty")
	}
	if creds.Credential == "" {
		t.Error("TURN credential must not be empty")
	}
	if !strings.Contains(creds.Username, "my-session-id") {
		t.Errorf("TURN username %q should contain session ID", creds.Username)
	}
}

// --- Phase 5 safety-gate tests ---

// TestBlockedSessionJoinRejected verifies that an "offer" relay message from a joiner
// who is blocked by (or has blocked) the session host is rejected with code="blocked".
//
// Uses an httptest.Server to stub the Supabase PostgREST /rest/v1/blocks endpoint,
// returning a non-empty row to simulate a block relationship.
func TestBlockedSessionJoinRejected(t *testing.T) {
	// Stub Supabase returning one block row.
	supaStub := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		// Non-empty array — block exists.
		fmt.Fprintln(w, `[{"blocker_uid":"host-uid"}]`)
	}))
	defer supaStub.Close()

	cfg := &config.Config{
		Port:               8080,
		JWTSecret:          "test-secret",
		MaxSessions:        200,
		SupabaseURL:        supaStub.URL,
		SupabaseServiceKey: "service-key",
	}
	h := NewHub(cfg)

	// Set up a session so handleRelay can get session.HostUID.
	if err := h.sessions.Register("sess-blk", "host-uid", "World", 4); err != nil {
		t.Fatalf("Register: %v", err)
	}

	joiner := &Client{
		uid:       "joiner-uid",
		sessionID: "sess-blk",
		send:      make(chan []byte, sendBufferSize),
	}

	payload := map[string]interface{}{
		"to_uid": "host-uid",
	}
	payloadBytes, _ := json.Marshal(payload)
	rawMsg := map[string]interface{}{
		"v":       1,
		"type":    "offer",
		"payload": json.RawMessage(payloadBytes),
	}
	rawBytes, _ := json.Marshal(rawMsg)

	h.handleMessage(joiner, rawBytes)

	select {
	case msg := <-joiner.send:
		var env envelope
		if err := json.Unmarshal(msg, &env); err != nil {
			t.Fatalf("response not valid JSON: %v", err)
		}
		if env.Type != "error" {
			t.Errorf("type = %q, want \"error\"", env.Type)
		}
		var errPayload struct {
			Code string `json:"code"`
		}
		if err := json.Unmarshal(env.Payload, &errPayload); err != nil {
			t.Fatalf("error payload not parseable: %v", err)
		}
		if errPayload.Code != "blocked" {
			t.Errorf("code = %q, want \"blocked\"", errPayload.Code)
		}
	default:
		t.Error("expected an error response in joiner.send, got nothing")
	}
}

// TestReportRateLimitFiveIn24h verifies that checkReportRateLimit returns false (i.e. rate-limited)
// when Supabase reports >= 5 rows for the reporter in the last 24h.
func TestReportRateLimitFiveIn24h(t *testing.T) {
	// Stub Supabase returning 5 report rows (at the limit — 6th would be rejected).
	callCount := 0
	supaStub := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		// Return 5 rows — reporter has hit the 5/24h cap.
		fmt.Fprintln(w, `[{"id":"r1"},{"id":"r2"},{"id":"r3"},{"id":"r4"},{"id":"r5"}]`)
	}))
	defer supaStub.Close()

	cfg := &config.Config{
		Port:               8080,
		JWTSecret:          "test-secret",
		MaxSessions:        200,
		SupabaseURL:        supaStub.URL,
		SupabaseServiceKey: "service-key",
	}
	h := NewHub(cfg)

	allowed, err := h.checkReportRateLimit("reporter-uid")
	if err != nil {
		t.Fatalf("checkReportRateLimit error: %v", err)
	}
	if allowed {
		t.Error("checkReportRateLimit should return false (rate-limited) when reporter has 5 reports in 24h")
	}
	if callCount == 0 {
		t.Error("expected at least one Supabase call")
	}
}

// TestConsentTokenSingleUse verifies that ConsentHandler.HandleConfirm:
//  1. Returns 200 on a valid unused token.
//  2. Returns 404 if the same token is presented again (single-use — token cleared).
//
// Both Supabase calls are stubbed via httptest.
func TestConsentTokenSingleUse(t *testing.T) {
	used := false
	supaStub := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.Method == http.MethodGet && strings.Contains(r.URL.Path, "parental_consents") {
			if !used {
				// First call: return a valid unconsumed row.
				expiry := time.Now().Add(7 * 24 * time.Hour).Format(time.RFC3339)
				fmt.Fprintf(w, `[{"child_uid":"child-uid","consented_at":null,"requested_at":"%s"}]`, expiry)
			} else {
				// Second call: token already cleared — no row found.
				fmt.Fprintln(w, `[]`)
			}
			return
		}
		if r.Method == http.MethodPatch {
			// PATCH to update consented_at or admin user metadata.
			used = true
			w.WriteHeader(http.StatusNoContent)
			return
		}
		w.WriteHeader(http.StatusOK)
		fmt.Fprintln(w, `{}`)
	}))
	defer supaStub.Close()

	cfg := &config.Config{
		Port:               8080,
		JWTSecret:          "test-secret",
		MaxSessions:        200,
		SupabaseURL:        supaStub.URL,
		SupabaseServiceKey: "service-key",
		ConsentBaseURL:     "example.com",
	}
	h := NewHub(cfg)
	ch := NewConsentHandler(h)

	// First request — should succeed.
	req1 := httptest.NewRequest(http.MethodGet, "/consent/confirm?token=VALIDTOKEN", nil)
	w1 := httptest.NewRecorder()
	ch.HandleConfirm(w1, req1)
	if w1.Code != http.StatusOK {
		t.Errorf("first confirm: got HTTP %d, want 200", w1.Code)
	}

	// Second request — token already consumed.
	req2 := httptest.NewRequest(http.MethodGet, "/consent/confirm?token=VALIDTOKEN", nil)
	w2 := httptest.NewRecorder()
	ch.HandleConfirm(w2, req2)
	if w2.Code != http.StatusNotFound {
		t.Errorf("second confirm (token reuse): got HTTP %d, want 404", w2.Code)
	}
}
