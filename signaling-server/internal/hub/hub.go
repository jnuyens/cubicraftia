// Package hub implements the WebSocket hub for the Cubicraftia signaling server.
// It manages client connections, session publishing, and WebRTC offer/answer/ICE relay.
// The hub never touches game state — it is a thin relay and session registry only.
package hub

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/cubicraftia/signaling-server/internal/config"
	"nhooyr.io/websocket"
)

const (
	// sessionIdleTimeout is how long a session can be inactive before it is pruned.
	// CONTEXT Area 2: 15-minute idle timeout.
	sessionIdleTimeout = 15 * time.Minute

	// pruneTicker controls how often idle sessions are checked.
	pruneTicker = 60 * time.Second

	// writeTimeout is the per-message write deadline on the WebSocket.
	writeTimeout = 10 * time.Second

	// sendBufferSize is the number of outbound messages buffered per client.
	sendBufferSize = 64
)

// envelope is the v1 JSON wire format for all messages.
// Every message carries "v":1 so clients can detect protocol mismatches.
type envelope struct {
	V       int             `json:"v"`
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

// Client represents a single connected WebSocket client.
type Client struct {
	uid       string
	sessionID string // session this client is currently in (may be empty)
	conn      *websocket.Conn
	send      chan []byte
}

// Hub manages all connected clients and the session registry.
type Hub struct {
	mu       sync.RWMutex
	clients  map[string]*Client // keyed by uid
	sessions *SessionRegistry
	cfg      *config.Config
}

// NewHub creates a Hub backed by the given config.
func NewHub(cfg *config.Config) *Hub {
	return &Hub{
		clients:  make(map[string]*Client),
		sessions: NewSessionRegistry(cfg.MaxSessions),
		cfg:      cfg,
	}
}

// Run starts background maintenance goroutines (idle-session pruner).
// Call this in a goroutine; it runs until ctx is cancelled.
func (h *Hub) Run(ctx context.Context) {
	ticker := time.NewTicker(pruneTicker)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			h.sessions.PruneIdle(sessionIdleTimeout)
		case <-ctx.Done():
			return
		}
	}
}

// HandleConn upgrades an HTTP request to a WebSocket connection, verifies the
// Supabase JWT, registers the client, and starts the read/write pumps.
// The JWT must be supplied as:
//   - Authorization: Bearer <token>  (preferred)
//   - ?token=<token>                 (query parameter fallback)
func (h *Hub) HandleConn(w http.ResponseWriter, r *http.Request) {
	// Extract JWT from header or query param.
	tokenStr := ""
	if auth := r.Header.Get("Authorization"); strings.HasPrefix(auth, "Bearer ") {
		tokenStr = strings.TrimPrefix(auth, "Bearer ")
	} else if q := r.URL.Query().Get("token"); q != "" {
		tokenStr = q
	}

	uid, err := VerifyJWT(tokenStr, h.cfg.JWTSecret)
	if err != nil {
		log.Printf("[hub] JWT verification failed: %v", err)
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Upgrade to WebSocket.
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		InsecureSkipVerify: false,
	})
	if err != nil {
		log.Printf("[hub] WebSocket upgrade error: %v", err)
		return
	}

	client := &Client{
		uid:  uid,
		conn: conn,
		send: make(chan []byte, sendBufferSize),
	}

	h.mu.Lock()
	// Replace any stale connection for the same uid (reconnect).
	if old, exists := h.clients[uid]; exists {
		close(old.send)
	}
	h.clients[uid] = client
	h.mu.Unlock()

	log.Printf("[hub] client connected: %s", uid)

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()

	// Start write pump in background.
	go client.writePump(ctx)

	// Read loop — blocks until the connection closes or an error occurs.
	h.readLoop(ctx, client)

	// Clean up.
	h.mu.Lock()
	if h.clients[uid] == client {
		delete(h.clients, uid)
	}
	h.mu.Unlock()
	conn.Close(websocket.StatusNormalClosure, "bye")
	log.Printf("[hub] client disconnected: %s", uid)
}

// readLoop reads messages from the client until the connection closes.
func (h *Hub) readLoop(ctx context.Context, client *Client) {
	for {
		_, raw, err := client.conn.Read(ctx)
		if err != nil {
			return
		}
		h.handleMessage(client, raw)
	}
}

// handleMessage dispatches a raw JSON message from a client to the appropriate handler.
// Unknown message types receive an error response.
func (h *Hub) handleMessage(client *Client, raw []byte) {
	var env envelope
	if err := json.Unmarshal(raw, &env); err != nil {
		client.send <- buildError("parse_error", "Invalid JSON envelope")
		return
	}
	if env.V != 1 {
		client.send <- buildError("version_mismatch", "Unsupported protocol version")
		return
	}

	switch env.Type {
	case "register":
		h.handleRegister(client, env.Payload)
	case "publish_session":
		h.handlePublishSession(client, env.Payload)
	case "unpublish_session":
		h.handleUnpublishSession(client, env.Payload)
	case "offer", "answer", "ice":
		h.handleRelay(client, env.Type, env.Payload, raw)
	case "update_host":
		h.handleUpdateHost(client, env.Payload)
	default:
		client.send <- buildError("unknown_type", "Unknown message type: "+env.Type)
	}
}

// handleRegister processes a "register" message.
// In v1 the client sends its uid and an optional session_id.
// Friend-online notification is deferred to the client via Supabase FriendsClient.
func (h *Hub) handleRegister(client *Client, payload json.RawMessage) {
	var p struct {
		UID       string `json:"uid"`
		SessionID string `json:"session_id"`
	}
	if err := json.Unmarshal(payload, &p); err != nil {
		client.send <- buildError("bad_payload", "register: invalid payload")
		return
	}
	if p.SessionID != "" {
		client.sessionID = p.SessionID
	}
	// v1: send empty session_list; client polls via FriendsClient for friend sessions.
	type sessionListMsg struct {
		V       int              `json:"v"`
		Type    string           `json:"type"`
		Payload []sessionListEntry `json:"payload"`
	}
	resp, _ := json.Marshal(sessionListMsg{V: 1, Type: "session_list", Payload: []sessionListEntry{}})
	client.send <- resp

	// Issue short-lived TURN credentials (coturn use-auth-secret) so the client can use
	// TURN relay fallback for symmetric-NAT/CGNAT peers. Re-issued on every (re)register,
	// including reconnect and host-failover promotion, so a fresh credential is always in hand.
	if h.cfg.TURNSharedSecret != "" {
		creds := GenerateTURNCredentials(client.uid, h.cfg.TURNSharedSecret, turnCredentialTTLSeconds)
		type turnCredsPayload struct {
			Username   string `json:"username"`
			Credential string `json:"credential"`
			TTL        int64  `json:"ttl"`
		}
		type turnCredsMsg struct {
			V       int              `json:"v"`
			Type    string           `json:"type"`
			Payload turnCredsPayload `json:"payload"`
		}
		if b, err := json.Marshal(turnCredsMsg{
			V:    1,
			Type: "turn_credentials",
			Payload: turnCredsPayload{
				Username:   creds.Username,
				Credential: creds.Credential,
				TTL:        turnCredentialTTLSeconds,
			},
		}); err == nil {
			client.send <- b
		}
	}
}

// handlePublishSession processes a "publish_session" message.
// Enforces the 4-peer max per session and the 200-session soft cap.
func (h *Hub) handlePublishSession(client *Client, payload json.RawMessage) {
	var p struct {
		SessionID string `json:"session_id"`
		WorldName string `json:"world_name"`
		MaxPeers  int    `json:"max_peers"`
	}
	if err := json.Unmarshal(payload, &p); err != nil {
		client.send <- buildError("bad_payload", "publish_session: invalid payload")
		return
	}
	if p.MaxPeers > 4 {
		client.send <- buildError("peer_limit_exceeded", "max_peers cannot exceed 4")
		return
	}
	if err := h.sessions.Register(p.SessionID, client.uid, p.WorldName, p.MaxPeers); err != nil {
		client.send <- buildError("publish_failed", err.Error())
		return
	}
	client.sessionID = p.SessionID
	// Acknowledge publication.
	ack := envelope{V: 1, Type: "session_published"}
	ackJSON, _ := json.Marshal(ack)
	client.send <- ackJSON
}

// handleUnpublishSession processes an "unpublish_session" message.
func (h *Hub) handleUnpublishSession(client *Client, payload json.RawMessage) {
	var p struct {
		SessionID string `json:"session_id"`
	}
	if err := json.Unmarshal(payload, &p); err != nil {
		client.send <- buildError("bad_payload", "unpublish_session: invalid payload")
		return
	}
	h.sessions.Unregister(p.SessionID)
	if client.sessionID == p.SessionID {
		client.sessionID = ""
	}
}

// handleRelay processes offer, answer, and ice messages by forwarding them to the target uid.
// For "offer" messages, enforces the block gate (T-05-E2) and consent gate (T-05-E3)
// before forwarding. Client-side checks are UX only; this is the hard enforcement point.
func (h *Hub) handleRelay(client *Client, msgType string, payload json.RawMessage, raw []byte) {
	var p struct {
		ToUID string `json:"to_uid"`
	}
	if err := json.Unmarshal(payload, &p); err != nil {
		client.send <- buildError("bad_payload", msgType+": missing to_uid")
		return
	}
	if p.ToUID == "" {
		client.send <- buildError("bad_payload", msgType+": to_uid is empty")
		return
	}
	// CR-04/CR-02: Enforce the 4-peer cap at join time. A new peer initiates with an
	// "offer" to the host. Check and increment PeerCount only on the first offer
	// from this client so that answer/ice messages are never blocked.
	// TryIncrementPeerCount performs the cap check and increment atomically under a
	// single lock, preventing the TOCTOU race that could allow a 5th peer to join.
	if msgType == "offer" && client.sessionID != "" {
		s := h.sessions.Get(client.sessionID)
		if s != nil {
			// T-05-E2: Block gate — reject if either peer has blocked the other.
			// Use the host UID from the session as the other party.
			hostUID := s.HostUID
			if client.uid != hostUID {
				blocked, err := h.isBlockedBetween(client.uid, hostUID)
				if err != nil {
					log.Printf("[hub] isBlockedBetween error (uid=%s, host=%s): %v — failing closed", client.uid, hostUID, err)
					client.send <- buildError("blocked", "join rejected")
					return
				}
				if blocked {
					client.send <- buildError("blocked", "join rejected: block relationship exists")
					return
				}
			}

			// T-05-E3: Consent gate — reject under-13 accounts without parental consent.
			consentRequired, err := h.isConsentRequired(client.uid)
			if err != nil {
				log.Printf("[hub] isConsentRequired error (uid=%s): %v — failing closed", client.uid, err)
				client.send <- buildError("consent_required", "join rejected: consent check failed")
				return
			}
			if consentRequired {
				client.send <- buildError("consent_required", "parental consent required before joining")
				return
			}

			// Atomic check-and-increment: if session is full this returns false.
			if !h.sessions.TryIncrementPeerCount(client.sessionID, s.MaxPeers) {
				client.send <- buildError("session_full", "session has reached maximum peers")
				return
			}
		}
	}
	// Touch session activity.
	if client.sessionID != "" {
		h.sessions.Touch(client.sessionID)
	}
	h.relay(client.uid, p.ToUID, raw)
}

// HandleAdminReports serves GET /admin/reports — returns a paginated JSON array of reports
// from the Supabase reports table. Requires Authorization: Bearer {ADMIN_SECRET}.
//
// Query params:
//   - page  (int, default 0) — zero-based page index
//   - limit (int, default 50, max 200)
func (h *Hub) HandleAdminReports(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	// Verify admin secret.
	auth := r.Header.Get("Authorization")
	expected := "Bearer " + h.cfg.AdminSecret
	if h.cfg.AdminSecret == "" || auth != expected {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Parse pagination params.
	page := 0
	limit := 50
	if v := r.URL.Query().Get("page"); v != "" {
		if n, err := parseInt(v); err == nil && n >= 0 {
			page = n
		}
	}
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := parseInt(v); err == nil && n > 0 && n <= 200 {
			limit = n
		}
	}
	offset := page * limit

	endpoint := fmt.Sprintf(
		"%s/rest/v1/reports?select=*&order=created_at.desc&limit=%d&offset=%d",
		h.cfg.SupabaseURL,
		limit,
		offset,
	)

	req, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	req.Header.Set("apikey", h.cfg.SupabaseServiceKey)
	req.Header.Set("Authorization", "Bearer "+h.cfg.SupabaseServiceKey)
	req.Header.Set("Prefer", "count=exact")

	supaClient := &http.Client{Timeout: 5 * time.Second}
	resp, err := supaClient.Do(req)
	if err != nil {
		log.Printf("[hub] HandleAdminReports: Supabase error: %v", err)
		http.Error(w, "upstream error", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		http.Error(w, "read error", http.StatusInternalServerError)
		return
	}

	// Forward Content-Range for total count if present.
	if cr := resp.Header.Get("Content-Range"); cr != "" {
		w.Header().Set("Content-Range", cr)
		w.Header().Set("X-Total-Count", extractTotalFromContentRange(cr))
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(resp.StatusCode)
	w.Write(body) //nolint:errcheck // best-effort write
}

// RequireAdminSecret is middleware that checks Authorization: Bearer {AdminSecret}.
// Wraps an http.HandlerFunc and rejects unauthenticated requests with 401.
func (h *Hub) RequireAdminSecret(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		expected := "Bearer " + h.cfg.AdminSecret
		if h.cfg.AdminSecret == "" || auth != expected {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}

// parseInt is a small helper to parse a decimal int from a query string value.
// parseInt parses a decimal integer query-string value.
// Uses strconv.Atoi to detect overflow on large inputs (WR-01).
func parseInt(s string) (int, error) {
	return strconv.Atoi(s)
}

// extractTotalFromContentRange parses the total count from a PostgREST Content-Range
// header value like "0-49/1234". Returns "" if the format is unexpected.
func extractTotalFromContentRange(cr string) string {
	// Format: "range/total" e.g. "0-49/1234" or "*/1234"
	parts := strings.SplitN(cr, "/", 2)
	if len(parts) == 2 {
		return parts[1]
	}
	return ""
}


// handleUpdateHost processes an "update_host" message (sent by peers after failover).
func (h *Hub) handleUpdateHost(client *Client, payload json.RawMessage) {
	var p struct {
		SessionID  string `json:"session_id"`
		NewHostUID string `json:"new_host_uid"`
	}
	if err := json.Unmarshal(payload, &p); err != nil {
		client.send <- buildError("bad_payload", "update_host: invalid payload")
		return
	}
	// CR-01: Verify the requesting client is a member of the session they are
	// trying to update. Without this check any authenticated client could hijack
	// any live session's host field.
	s := h.sessions.Get(p.SessionID)
	if s == nil || (s.HostUID != client.uid && client.sessionID != p.SessionID) {
		client.send <- buildError("unauthorized", "not a member of this session")
		return
	}
	// CR-12: Verify the new host UID refers to a currently-connected client.
	// If the new host disconnected before this message was processed, skip the
	// UpdateHost call and return an error so the caller can retry with a live peer.
	h.mu.RLock()
	_, connected := h.clients[p.NewHostUID]
	h.mu.RUnlock()
	if !connected {
		client.send <- buildError("new_host_not_connected", "new host UID is not connected")
		return
	}
	if err := h.sessions.UpdateHost(p.SessionID, p.NewHostUID); err != nil {
		client.send <- buildError("update_host_failed", err.Error())
		return
	}
	// Relay a host_updated notification to the new host.
	type hostUpdatedPayload struct {
		SessionID  string `json:"session_id"`
		NewHostUID string `json:"new_host_uid"`
	}
	notifPayload, _ := json.Marshal(hostUpdatedPayload{SessionID: p.SessionID, NewHostUID: p.NewHostUID})
	notif, _ := json.Marshal(envelope{V: 1, Type: "host_updated", Payload: notifPayload})
	h.relayDirect(p.NewHostUID, notif)
}
