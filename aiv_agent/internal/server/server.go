package server

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/sandboxcsp/aiv_agent/internal/auth"
	"github.com/sandboxcsp/aiv_agent/internal/metrics"
)

// Config holds the server configuration.
type Config struct {
	Port     int
	CertFile string
	KeyFile  string
	CAFile   string
}

// Server is the aiv_agent HTTP server.
type Server struct {
	httpServer *http.Server
	cfg        Config
}

// New creates a new Server with mTLS configured.
func New(cfg Config) (*Server, error) {
	tlsConfig, err := auth.LoadTLSConfig(cfg.CertFile, cfg.KeyFile, cfg.CAFile)
	if err != nil {
		return nil, fmt.Errorf("tls config: %w", err)
	}

	mux := http.NewServeMux()
	s := &Server{cfg: cfg}
	s.registerRoutes(mux)

	s.httpServer = &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.Port),
		Handler:      withLogging(mux),
		TLSConfig:    tlsConfig,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 60 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	return s, nil
}

// Start begins listening with TLS.
func (s *Server) Start() error {
	log.Printf("listening on :%d (mTLS enabled)", s.cfg.Port)
	return s.httpServer.ListenAndServeTLS(s.cfg.CertFile, s.cfg.KeyFile)
}

// Stop gracefully shuts down the server.
func (s *Server) Stop() {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := s.httpServer.Shutdown(ctx); err != nil {
		log.Printf("shutdown error: %v", err)
	}
}

func (s *Server) registerRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/health", s.handleHealth)
	mux.HandleFunc("/metrics/performance", s.handlePerformance)
	mux.HandleFunc("/metrics/disk", s.handleDisk)
	mux.HandleFunc("/metrics/network", s.handleNetwork)
	mux.HandleFunc("/metrics/processes", s.handleProcesses)
	mux.HandleFunc("/metrics/services", s.handleServices)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"status": "ok",
		"agent":  "aiv_agent",
	})
}

func (s *Server) handlePerformance(w http.ResponseWriter, r *http.Request) {
	data, err := metrics.CollectPerformance()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, data)
}

func (s *Server) handleDisk(w http.ResponseWriter, r *http.Request) {
	data, err := metrics.CollectDisk()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, data)
}

func (s *Server) handleNetwork(w http.ResponseWriter, r *http.Request) {
	data, err := metrics.CollectNetwork()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, data)
}

func (s *Server) handleProcesses(w http.ResponseWriter, r *http.Request) {
	data, err := metrics.CollectProcesses()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, data)
}

func (s *Server) handleServices(w http.ResponseWriter, r *http.Request) {
	data, err := metrics.CollectServices()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, data)
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("json encode error: %v", err)
	}
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

// withLogging wraps a handler with request logging.
func withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s [%v]", r.Method, r.URL.Path, r.RemoteAddr, time.Since(start))
	})
}
