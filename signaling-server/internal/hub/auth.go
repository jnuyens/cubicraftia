// Package hub contains the WebSocket hub, session registry, relay, and auth logic.
package hub

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

// jwtHeader is the expected base64url-encoded header for HS256 JWTs.
// We verify the algorithm matches before trusting the signature.
const jwtHeaderPrefix = `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9` // {"alg":"HS256","typ":"JWT"}

// jwtClaims holds the standard JWT claims we care about.
type jwtClaims struct {
	Sub string `json:"sub"`
	Exp int64  `json:"exp"`
}

// VerifyJWT parses and verifies a Supabase HS256 JWT.
// It returns the uid (the "sub" claim) on success, or an error if the token is
// missing, malformed, expired, or has an invalid signature.
//
// This implementation uses only the standard library (encoding/base64,
// encoding/json, crypto/hmac, crypto/sha256) — no third-party JWT library.
func VerifyJWT(tokenString string, secret string) (uid string, err error) {
	if tokenString == "" {
		return "", errors.New("token is empty")
	}

	parts := strings.Split(tokenString, ".")
	if len(parts) != 3 {
		return "", errors.New("token must have three parts")
	}

	// Verify the header declares HS256.
	// We accept any header that decodes to alg=HS256 — not just the canonical
	// pre-computed prefix — so tests can pass arbitrary valid headers.
	headerJSON, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return "", errors.New("invalid header encoding")
	}
	var header struct {
		Alg string `json:"alg"`
		Typ string `json:"typ"`
	}
	if err := json.Unmarshal(headerJSON, &header); err != nil {
		return "", errors.New("invalid header JSON")
	}
	if header.Alg != "HS256" {
		return "", errors.New("unsupported algorithm: " + header.Alg)
	}

	// Verify HMAC-SHA256 signature.
	// The signature covers: base64url(header) + "." + base64url(payload)
	signingInput := parts[0] + "." + parts[1]
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(signingInput))
	expectedSig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(expectedSig), []byte(parts[2])) {
		return "", errors.New("invalid signature")
	}

	// Decode payload.
	payloadJSON, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return "", errors.New("invalid payload encoding")
	}
	var claims jwtClaims
	if err := json.Unmarshal(payloadJSON, &claims); err != nil {
		return "", errors.New("invalid payload JSON")
	}

	// Verify expiry.
	if claims.Exp == 0 {
		return "", errors.New("token has no expiry")
	}
	if time.Now().Unix() > claims.Exp {
		return "", errors.New("token is expired")
	}

	// Extract subject (Supabase user UUID).
	if claims.Sub == "" {
		return "", errors.New("token has no sub claim")
	}

	return claims.Sub, nil
}
