#!/usr/bin/env bash
set -x
cd /workspaces/ViMax || exit 1
sudo apt-get update -qq && sudo apt-get install -y -qq ffmpeg >/dev/null 2>&1
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
cp -n configs/agent.example.yaml configs/agent.local.yaml || true
( cd web && npm install --no-audit --no-fund && npm run build )
uv sync --frozen --no-dev
nohup env VIMAX_PYTHON_CMD=/workspaces/ViMax/.venv/bin/python3 VIMAX_WEB_HOST=0.0.0.0 node web/server.mjs > /tmp/vimax.log 2>&1 &
sleep 10
HEALTH=$(curl -s -m 5 http://127.0.0.1:4173/api/health)
curl -sL -o /tmp/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x /tmp/cloudflared
nohup /tmp/cloudflared tunnel --url http://localhost:4173 --no-autoupdate > /tmp/cf.log 2>&1 &
sleep 40
URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/cf.log | head -1)
gh codespace ports visibility 4173:public -c "$CODESPACE_NAME" > /tmp/portvis.txt 2>&1 || true
{
  echo "tunnel_url: $URL"
  echo "health: $HEALTH"
  echo "portvis: $(cat /tmp/portvis.txt)"
  echo "when: $(date -u)"
} > PUBLIC_URL.txt
git add PUBLIC_URL.txt
git -c user.email=agent@users.noreply.github.com -c user.name=agent commit -m "publish public url" || true
git push || true
