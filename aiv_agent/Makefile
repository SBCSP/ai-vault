VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BINARY  := aiv_agent
GOFLAGS := -trimpath
LDFLAGS := -s -w -X main.Version=$(VERSION)

# Build targets
GOOS_LINUX   := linux
GOARCH_AMD64 := amd64

BUILD_DIR    := build
RPM_DIR      := $(BUILD_DIR)/rpm

.PHONY: all build build-linux clean rpm

all: build

## build: Build for the current platform
build:
	go build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o $(BUILD_DIR)/$(BINARY) ./cmd/aiv_agent

## build-linux: Cross-compile for Linux amd64 (for RPM packaging)
build-linux:
	GOOS=$(GOOS_LINUX) GOARCH=$(GOARCH_AMD64) go build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o $(BUILD_DIR)/$(BINARY)-linux-amd64 ./cmd/aiv_agent

## rpm: Build an RPM package (requires rpmbuild)
rpm: build-linux
	@echo "Building RPM for version $(VERSION)..."
	mkdir -p $(RPM_DIR)/SOURCES $(RPM_DIR)/SPECS $(RPM_DIR)/BUILD $(RPM_DIR)/RPMS $(RPM_DIR)/SRPMS

	# Copy binary and service file into SOURCES
	cp $(BUILD_DIR)/$(BINARY)-linux-amd64 $(RPM_DIR)/SOURCES/$(BINARY)
	cp packaging/systemd/aiv_agent.service $(RPM_DIR)/SOURCES/aiv_agent.service

	# Copy certs if they exist (bundled by AI VaultIO at download time)
	@if [ -f certs/server.crt ]; then cp certs/server.crt $(RPM_DIR)/SOURCES/; fi
	@if [ -f certs/server.key ]; then cp certs/server.key $(RPM_DIR)/SOURCES/; fi
	@if [ -f certs/ca.crt ]; then cp certs/ca.crt $(RPM_DIR)/SOURCES/; fi

	# Copy spec
	cp packaging/rpm/aiv_agent.spec $(RPM_DIR)/SPECS/

	# Build RPM
	rpmbuild --define "_topdir $(CURDIR)/$(RPM_DIR)" \
		--define "_version $(VERSION)" \
		--define "_sourcedir $(CURDIR)/$(RPM_DIR)/SOURCES" \
		-bb $(RPM_DIR)/SPECS/aiv_agent.spec

	@echo "RPM built: $$(find $(RPM_DIR)/RPMS -name '*.rpm')"

## rpm-fpm: Build RPM using fpm (simpler alternative to rpmbuild)
rpm-fpm: build-linux
	@echo "Building RPM with fpm for version $(VERSION)..."
	mkdir -p $(BUILD_DIR)/rpm-staging/usr/local/bin
	mkdir -p $(BUILD_DIR)/rpm-staging/etc/aiv_agent
	mkdir -p $(BUILD_DIR)/rpm-staging/usr/lib/systemd/system

	cp $(BUILD_DIR)/$(BINARY)-linux-amd64 $(BUILD_DIR)/rpm-staging/usr/local/bin/$(BINARY)
	chmod 755 $(BUILD_DIR)/rpm-staging/usr/local/bin/$(BINARY)
	cp packaging/systemd/aiv_agent.service $(BUILD_DIR)/rpm-staging/usr/lib/systemd/system/

	# Copy certs if they exist
	@if [ -f certs/server.crt ]; then cp certs/server.crt $(BUILD_DIR)/rpm-staging/etc/aiv_agent/; fi
	@if [ -f certs/server.key ]; then cp certs/server.key $(BUILD_DIR)/rpm-staging/etc/aiv_agent/; fi
	@if [ -f certs/ca.crt ]; then cp certs/ca.crt $(BUILD_DIR)/rpm-staging/etc/aiv_agent/; fi

	fpm -s dir -t rpm \
		-n $(BINARY) \
		-v $(VERSION) \
		--description "AI VaultIO Remote Monitoring Agent" \
		--after-install packaging/rpm/postinstall.sh \
		--before-remove packaging/rpm/preremove.sh \
		-C $(BUILD_DIR)/rpm-staging \
		.

	mv *.rpm $(BUILD_DIR)/ 2>/dev/null || true
	@echo "RPM built in $(BUILD_DIR)/"

## clean: Remove build artifacts
clean:
	rm -rf $(BUILD_DIR)

## help: Show this help
help:
	@grep -E '^##' Makefile | sed 's/## //' | column -t -s ':'
