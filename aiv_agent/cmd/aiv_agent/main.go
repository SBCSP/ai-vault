package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/sandboxcsp/aiv_agent/internal/server"
)

// Version is set at build time via -ldflags
var Version = "dev"

func main() {
	port := flag.Int("port", 9090, "port to listen on")
	certFile := flag.String("cert", "/etc/aiv_agent/server.crt", "path to server TLS certificate")
	keyFile := flag.String("key", "/etc/aiv_agent/server.key", "path to server TLS private key")
	caFile := flag.String("ca", "/etc/aiv_agent/ca.crt", "path to CA certificate for client verification")
	showVersion := flag.Bool("version", false, "print version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Printf("aiv_agent %s\n", Version)
		os.Exit(0)
	}

	log.Printf("aiv_agent %s starting on port %d", Version, *port)

	cfg := server.Config{
		Port:     *port,
		CertFile: *certFile,
		KeyFile:  *keyFile,
		CAFile:   *caFile,
	}

	srv, err := server.New(cfg)
	if err != nil {
		log.Fatalf("failed to create server: %v", err)
	}

	// Graceful shutdown on SIGINT/SIGTERM
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		if err := srv.Start(); err != nil {
			log.Fatalf("server error: %v", err)
		}
	}()

	<-stop
	log.Println("shutting down...")
	srv.Stop()
}
