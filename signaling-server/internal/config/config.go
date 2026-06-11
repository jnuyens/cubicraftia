// Package config loads runtime configuration from environment variables.
// All fields can be overridden by CLI flags in cmd/signaling/main.go.
package config

import (
	"log"
	"os"
	"strconv"
)

// Config holds all runtime configuration for the signaling server.
type Config struct {
	// Port is the TCP port to listen on. Default: 8080.
	Port int

	// SupabaseURL is the base URL of the self-hosted Supabase instance.
	// Used for server-to-server calls (blocks check, consent, reports).
	SupabaseURL string

	// SupabaseServiceKey is the Supabase service-role API key.
	// It bypasses Row-Level Security for server-side enforcement checks.
	// Set via env var SUPABASE_SERVICE_KEY.
	SupabaseServiceKey string

	// JWTSecret is the Supabase JWT secret (HS256 shared secret).
	// Every WebSocket connection must present a valid token signed with this secret.
	// Set via env var SUPABASE_JWT_SECRET.
	JWTSecret string

	// MaxSessions is the soft cap on concurrent published sessions.
	// When exceeded, the server logs an operator alert. Default: 200.
	MaxSessions int

	// AdminSecret is the bearer token required for /admin/reports.
	// Set via env var ADMIN_SECRET.
	AdminSecret string

	// SMTP fields for parental consent email delivery.
	// Set via env vars SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD, SMTP_FROM.
	SMTPHost     string
	SMTPPort     int
	SMTPUser     string
	SMTPPassword string
	SMTPFrom     string

	// ConsentBaseURL is the public base URL used when constructing consent/revoke links.
	// Set via env var CONSENT_BASE_URL.
	ConsentBaseURL string

	// TURNSharedSecret is the coturn use-auth-secret shared secret.
	// Set via env var TURN_SHARED_SECRET.
	TURNSharedSecret string
}

// Load reads configuration from environment variables and returns a populated Config.
// Missing optional variables use their stated defaults.
// A missing JWTSecret is logged as a warning (the server will reject all connections).
func Load() Config {
	port := 8080
	if v := os.Getenv("PORT"); v != "" {
		if p, err := strconv.Atoi(v); err == nil {
			port = p
		}
	}

	maxSessions := 200
	if v := os.Getenv("MAX_SESSIONS"); v != "" {
		if m, err := strconv.Atoi(v); err == nil {
			maxSessions = m
		}
	}

	smtpPort := 587
	if v := os.Getenv("SMTP_PORT"); v != "" {
		if p, err := strconv.Atoi(v); err == nil {
			smtpPort = p
		}
	}

	jwtSecret := os.Getenv("SUPABASE_JWT_SECRET")
	if jwtSecret == "" {
		log.Println("[config] WARNING: SUPABASE_JWT_SECRET is not set — all WebSocket connections will be rejected")
	}

	adminSecret := os.Getenv("ADMIN_SECRET")
	if adminSecret == "" {
		log.Println("[config] WARNING: ADMIN_SECRET is not set — /admin/reports will reject all requests")
	}

	return Config{
		Port:               port,
		SupabaseURL:        os.Getenv("SUPABASE_URL"),
		SupabaseServiceKey: os.Getenv("SUPABASE_SERVICE_KEY"),
		JWTSecret:          jwtSecret,
		MaxSessions:        maxSessions,
		AdminSecret:        adminSecret,
		SMTPHost:           os.Getenv("SMTP_HOST"),
		SMTPPort:           smtpPort,
		SMTPUser:           os.Getenv("SMTP_USER"),
		SMTPPassword:       os.Getenv("SMTP_PASSWORD"),
		SMTPFrom:           os.Getenv("SMTP_FROM"),
		ConsentBaseURL:     os.Getenv("CONSENT_BASE_URL"),
		TURNSharedSecret:   os.Getenv("TURN_SHARED_SECRET"),
	}
}
