package hub

import (
	"crypto/hmac"
	"crypto/sha1" //nolint:gosec // coturn use-auth-secret requires HMAC-SHA1 specifically (WR-01)
	"encoding/base64"
	"errors"
	"fmt"
	"log"
	"sync"
	"time"
)

// Session holds the in-memory state for a published game session.
type Session struct {
	ID           string
	HostUID      string
	WorldName    string
	PeerCount    int
	MaxPeers     int
	PublishedAt  time.Time
	LastActivity time.Time
}

// TURNCredentials holds short-lived TURN credentials derived from the coturn
// use-auth-secret mode. The credential is an HMAC-SHA1 of the username using
// the shared static-auth-secret.
type TURNCredentials struct {
	Username   string
	Credential string
}

// turnCredentialTTLSeconds is the lifetime of an issued TURN credential (1 hour).
// The client refreshes on every (re)register, so sessions longer than this still get
// fresh credentials on any reconnect or host-failover promotion.
const turnCredentialTTLSeconds int64 = 3600

// GenerateTURNCredentials creates time-limited TURN credentials for a session
// using coturn's use-auth-secret mode. The username is
// "<unix_timestamp_ttl>:<session_id>" and the credential is the HMAC-SHA1 of
// the username using the shared secret.
//
// ttlSeconds is the credential lifetime (e.g. 3600 for 1 hour).
func GenerateTURNCredentials(sessionID string, sharedSecret string, ttlSeconds int64) TURNCredentials {
	expiry := time.Now().Unix() + ttlSeconds
	username := fmt.Sprintf("%d:%s", expiry, sessionID)
	// WR-01: coturn use-auth-secret mode requires HMAC-SHA1 specifically.
	// Using SHA256 causes all TURN relay connections to be rejected by coturn.
	mac := hmac.New(sha1.New, []byte(sharedSecret)) //nolint:gosec // required by coturn protocol
	mac.Write([]byte(username))
	credential := base64.StdEncoding.EncodeToString(mac.Sum(nil))
	return TURNCredentials{Username: username, Credential: credential}
}

// SessionRegistry is a thread-safe in-memory registry of published sessions.
type SessionRegistry struct {
	mu          sync.RWMutex
	sessions    map[string]*Session
	maxSessions int
}

// NewSessionRegistry creates an empty SessionRegistry with the given session cap.
func NewSessionRegistry(maxSessions int) *SessionRegistry {
	return &SessionRegistry{
		sessions:    make(map[string]*Session),
		maxSessions: maxSessions,
	}
}

// Register publishes a new session. Returns an error if:
//   - a session with the same ID already exists
//   - maxPeers > 4 (enforcing the 4-peer cap from CONTEXT Area 2)
//
// A warning is logged when the total session count exceeds maxSessions (soft cap).
func (r *SessionRegistry) Register(sessionID, hostUID, worldName string, maxPeers int) error {
	if maxPeers > 4 {
		return errors.New("max_peers cannot exceed 4")
	}
	if maxPeers < 1 {
		maxPeers = 4
	}

	r.mu.Lock()
	defer r.mu.Unlock()

	if _, exists := r.sessions[sessionID]; exists {
		return fmt.Errorf("session %q already exists", sessionID)
	}

	r.sessions[sessionID] = &Session{
		ID:           sessionID,
		HostUID:      hostUID,
		WorldName:    worldName,
		PeerCount:    1, // host counts as the first peer
		MaxPeers:     maxPeers,
		PublishedAt:  time.Now(),
		LastActivity: time.Now(),
	}

	if len(r.sessions) > r.maxSessions {
		log.Printf("[session] OPERATOR ALERT: session count %d exceeds soft cap %d — consider horizontal scaling", len(r.sessions), r.maxSessions)
	}

	return nil
}

// Unregister removes a session from the registry. Silently does nothing if not found.
func (r *SessionRegistry) Unregister(sessionID string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.sessions, sessionID)
}

// UpdateHost changes the host UID of an existing session (called after failover).
// Returns an error if the session does not exist.
func (r *SessionRegistry) UpdateHost(sessionID, newHostUID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	s, ok := r.sessions[sessionID]
	if !ok {
		return fmt.Errorf("session %q not found", sessionID)
	}
	s.HostUID = newHostUID
	s.LastActivity = time.Now()
	return nil
}

// Get returns the session with the given ID, or nil if not found.
func (r *SessionRegistry) Get(sessionID string) *Session {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.sessions[sessionID]
}

// IncrementPeerCount atomically increments the PeerCount for a session.
// Called when a new peer sends its first offer to the host (CR-02).
// Silently does nothing if the session does not exist.
func (r *SessionRegistry) IncrementPeerCount(sessionID string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if s, ok := r.sessions[sessionID]; ok {
		s.PeerCount++
	}
}

// TryIncrementPeerCount atomically checks PeerCount < maxPeers and increments if so.
// Returns true if the increment happened (peer is allowed to join), false if the
// session is full or does not exist.  The check and increment happen under a single
// lock acquisition, eliminating the TOCTOU race in handleRelay (CR-04).
func (r *SessionRegistry) TryIncrementPeerCount(sessionID string, maxPeers int) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	s, ok := r.sessions[sessionID]
	if !ok || s.PeerCount >= maxPeers {
		return false
	}
	s.PeerCount++
	return true
}

// Touch updates the LastActivity timestamp for a session.
// Used to keep idle-timeout accurate when peers exchange messages.
func (r *SessionRegistry) Touch(sessionID string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if s, ok := r.sessions[sessionID]; ok {
		s.LastActivity = time.Now()
	}
}

// ListByUIDs returns all sessions whose HostUID is in the provided uids slice.
// This is a simple in-memory scan; acceptable for the 200-session cap.
func (r *SessionRegistry) ListByUIDs(uids []string) []*Session {
	r.mu.RLock()
	defer r.mu.RUnlock()
	uidSet := make(map[string]struct{}, len(uids))
	for _, u := range uids {
		uidSet[u] = struct{}{}
	}
	var result []*Session
	for _, s := range r.sessions {
		if _, ok := uidSet[s.HostUID]; ok {
			result = append(result, s)
		}
	}
	return result
}

// PruneIdle removes sessions whose LastActivity is older than timeout.
// Should be called periodically (e.g., every 60 s) by Hub.Run().
func (r *SessionRegistry) PruneIdle(timeout time.Duration) {
	r.mu.Lock()
	defer r.mu.Unlock()
	now := time.Now()
	for id, s := range r.sessions {
		if now.Sub(s.LastActivity) > timeout {
			log.Printf("[session] pruning idle session %q (inactive for %s)", id, now.Sub(s.LastActivity).Round(time.Second))
			delete(r.sessions, id)
		}
	}
}

// sessionListEntry is the JSON shape for a single session in a session_list payload.
// published_at_unix is a Unix timestamp (seconds) used by clients to compute session age
// for the unverified-account join gate (CONTEXT Area 3: unverified accounts cannot join
// sessions older than 24 hours).
type sessionListEntry struct {
	SessionID       string `json:"session_id"`
	HostUID         string `json:"host_uid"`
	WorldName       string `json:"world_name"`
	PeerCount       int    `json:"peer_count"`
	PublishedAtUnix int64  `json:"published_at_unix"`
}

// toListEntry converts a Session to a sessionListEntry for the session_list payload.
func (s *Session) toListEntry() sessionListEntry {
	return sessionListEntry{
		SessionID:       s.ID,
		HostUID:         s.HostUID,
		WorldName:       s.WorldName,
		PeerCount:       s.PeerCount,
		PublishedAtUnix: s.PublishedAt.Unix(),
	}
}
