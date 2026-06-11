// Package main is the entry point for the Cubicraftia WebRTC signaling server.
// It reads configuration from environment variables (overridable via flags),
// starts the WebSocket hub, and handles graceful shutdown on SIGINT/SIGTERM.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/cubicraftia/signaling-server/internal/config"
	"github.com/cubicraftia/signaling-server/internal/hub"
)

func main() {
	// Load defaults from environment variables.
	cfg := config.Load()

	// CLI flags override env vars.
	flag.IntVar(&cfg.Port, "port", cfg.Port, "TCP port to listen on (env: PORT)")
	flag.StringVar(&cfg.SupabaseURL, "supabase-url", cfg.SupabaseURL, "Supabase base URL (env: SUPABASE_URL)")
	flag.StringVar(&cfg.JWTSecret, "jwt-secret", cfg.JWTSecret, "Supabase JWT secret (env: SUPABASE_JWT_SECRET)")
	flag.IntVar(&cfg.MaxSessions, "max-sessions", cfg.MaxSessions, "Soft cap on concurrent sessions (env: MAX_SESSIONS)")
	flag.StringVar(&cfg.AdminSecret, "admin-secret", cfg.AdminSecret, "Bearer token for /admin/reports (env: ADMIN_SECRET)")
	flag.StringVar(&cfg.ConsentBaseURL, "consent-base-url", cfg.ConsentBaseURL, "Base URL for consent links (env: CONSENT_BASE_URL)")
	flag.Parse()

	h := hub.NewHub(&cfg)
	consentHandler := hub.NewConsentHandler(h)

	mux := http.NewServeMux()
	mux.HandleFunc("/ws", h.HandleConn)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintln(w, "ok")
	})

	// Phase 5: Parental consent lifecycle endpoints.
	mux.HandleFunc("/consent/request", consentHandler.HandleRequest)
	mux.HandleFunc("/consent/confirm", consentHandler.HandleConfirm)
	mux.HandleFunc("/consent/revoke", consentHandler.HandleRevoke)

	// Phase 5: Operator moderation reports endpoint (ADMIN_SECRET required).
	mux.HandleFunc("/admin/reports", h.HandleAdminReports)

	addr := fmt.Sprintf(":%d", cfg.Port)
	srv := &http.Server{
		Addr:         addr,
		Handler:      mux,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  90 * time.Second,
	}

	// Start the hub background loop.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go h.Run(ctx)

	// Start HTTP server in a goroutine.
	go func() {
		log.Printf("[main] signaling server listening on %s", addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[main] ListenAndServe: %v", err)
		}
	}()

	// Wait for SIGINT or SIGTERM.
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	sig := <-quit
	log.Printf("[main] received signal %s — shutting down", sig)

	// Graceful shutdown with 10-second deadline.
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("[main] server shutdown error: %v", err)
	}
	cancel() // stop hub background loop
	log.Println("[main] shutdown complete")
}
