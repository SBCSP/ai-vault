Name:           aiv_agent
Version:        %{_version}
Release:        1%{?dist}
Summary:        AI VaultIO Remote Monitoring Agent
License:        Proprietary
URL:            https://github.com/sandboxcsp/ai-vault

%description
Lightweight monitoring agent for AI VaultIO. Runs as a systemd service
and exposes system metrics over mTLS for the AI VaultIO desktop app.

%install
mkdir -p %{buildroot}/usr/local/bin
mkdir -p %{buildroot}/etc/aiv_agent
mkdir -p %{buildroot}/usr/lib/systemd/system

cp %{_sourcedir}/aiv_agent %{buildroot}/usr/local/bin/aiv_agent
cp %{_sourcedir}/aiv_agent.service %{buildroot}/usr/lib/systemd/system/aiv_agent.service

# Install certs if bundled
if [ -f %{_sourcedir}/server.crt ]; then
    cp %{_sourcedir}/server.crt %{buildroot}/etc/aiv_agent/server.crt
fi
if [ -f %{_sourcedir}/server.key ]; then
    cp %{_sourcedir}/server.key %{buildroot}/etc/aiv_agent/server.key
fi
if [ -f %{_sourcedir}/ca.crt ]; then
    cp %{_sourcedir}/ca.crt %{buildroot}/etc/aiv_agent/ca.crt
fi

%pre
# Create service user if it doesn't exist
getent group aiv_agent >/dev/null || groupadd -r aiv_agent
getent passwd aiv_agent >/dev/null || useradd -r -g aiv_agent -d /etc/aiv_agent -s /sbin/nologin -c "AI VaultIO Agent" aiv_agent

%post
# Set permissions on cert files
chmod 600 /etc/aiv_agent/*.key 2>/dev/null || true
chmod 644 /etc/aiv_agent/*.crt 2>/dev/null || true
chown -R aiv_agent:aiv_agent /etc/aiv_agent

systemctl daemon-reload
systemctl enable aiv_agent.service
systemctl start aiv_agent.service
echo "aiv_agent installed and started on port 9090"

%preun
if [ $1 -eq 0 ]; then
    systemctl stop aiv_agent.service 2>/dev/null || true
    systemctl disable aiv_agent.service 2>/dev/null || true
fi

%postun
if [ $1 -eq 0 ]; then
    systemctl daemon-reload
fi

%files
%attr(755, root, root) /usr/local/bin/aiv_agent
%attr(644, root, root) /usr/lib/systemd/system/aiv_agent.service
%dir %attr(750, aiv_agent, aiv_agent) /etc/aiv_agent
%config(noreplace) %attr(644, aiv_agent, aiv_agent) /etc/aiv_agent/ca.crt
%config(noreplace) %attr(644, aiv_agent, aiv_agent) /etc/aiv_agent/server.crt
%config(noreplace) %attr(600, aiv_agent, aiv_agent) /etc/aiv_agent/server.key
