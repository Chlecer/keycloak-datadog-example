#!/bin/bash
set -e

echo ">>> Updating packages..."
apt-get update -qq

echo ">>> Installing prerequisites..."
apt-get install -y -qq curl gnupg apt-transport-https software-properties-common python3 python3-pip sudo

echo ">>> Installing Ansible..."
pip3 install --quiet ansible

echo ">>> Creating fake Datadog Agent configuration (simulating already installed agent)..."
mkdir -p /etc/datadog-agent
cat > /etc/datadog-agent/datadog.yaml << 'EOF'
# Fake Datadog Agent config for testing
api_key: fake-api-key-1234567890abcdef

site: datadoghq.eu

tags:
  - "env:test"
  - "team:platform"
  - "os:linux"

logs_enabled: true
EOF

echo ">>> Creating a dummy systemd service so the handler doesn't fail hard..."
mkdir -p /etc/systemd/system
cat > /etc/systemd/system/datadog-agent.service << 'EOF'
[Unit]
Description=Dummy Datadog Agent for testing

[Service]
Type=oneshot
ExecStart=/bin/true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload || true
systemctl enable datadog-agent || true
systemctl start datadog-agent || true

echo ""
echo ">>> Test environment is ready!"
echo ">>> Current Datadog tags:"
grep -A 20 '^tags:' /etc/datadog-agent/datadog.yaml || true
echo ""
echo "You can now run:"
echo "  ansible-playbook -i inventory/hosts.yml playbook.yml --connection=local"
