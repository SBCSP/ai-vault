#!/bin/bash
set -e

# Create service user
if ! id -u aiv_agent >/dev/null 2>&1; then
    useradd -r -s /sbin/nologin -d /etc/aiv_agent -c "AI VaultIO Agent" aiv_agent
fi

# Set permissions
chmod 600 /etc/aiv_agent/*.key 2>/dev/null || true
chmod 644 /etc/aiv_agent/*.crt 2>/dev/null || true
chown -R aiv_agent:aiv_agent /etc/aiv_agent

# Enable and start
systemctl daemon-reload
systemctl enable aiv_agent.service
systemctl start aiv_agent.service

echo ""
echo "============================================"
echo "  aiv_agent installed successfully!"
echo "  Listening on port 9090 (mTLS)"
echo "  Service: systemctl status aiv_agent"
echo "  Logs:    journalctl -u aiv_agent -f"
echo "============================================"
echo ""
