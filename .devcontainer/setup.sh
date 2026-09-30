#!/usr/bin/env bash
set -x
cd /workspaces/ViMax || exit 1
sudo apt-get update -qq && sudo apt-get install -y -qq ffmpeg >/dev/null 2>&1
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
cp -n configs/agent.example.yaml configs/agent.local.yaml || true
( cd web && npm install --no-audit --no-fund && npm run build )
uv sync --frozen --no-dev
pkill -f "web/server.mjs" 2>/dev/null; pkill -f cloudflared 2>/dev/null; pkill -f "ollama serve" 2>/dev/null; sleep 2
setsid nohup bash -c 'while true; do VIMAX_PYTHON_CMD=/workspaces/ViMax/.venv/bin/python3 VIMAX_WEB_HOST=0.0.0.0 node /workspaces/ViMax/web/server.mjs >> /tmp/vimax.log 2>&1; sleep 5; done' >/dev/null 2>&1 &
sleep 12
HEALTH=$(curl -s -m 5 http://127.0.0.1:4173/api/health)
curl -sL -o /tmp/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x /tmp/cloudflared
setsid nohup /tmp/cloudflared tunnel --url http://localhost:4173 --no-autoupdate > /tmp/cf.log 2>&1 &
sleep 45
URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/cf.log | tail -1)

# ===== Ollama relay server (for dhruv CLI + PocketPal) =====
if [ ! -x /usr/local/bin/ollama ]; then
  curl -fsSL https://ollama.com/install.sh | sudo bash >/tmp/ollama-install.log 2>&1
fi
setsid nohup bash -c 'while true; do OLLAMA_HOST=0.0.0.0:11434 /usr/local/bin/ollama serve >> /tmp/ollama.log 2>&1; sleep 5; done' >/dev/null 2>&1 &
sleep 10
/usr/local/bin/ollama pull gemma3:270m >> /tmp/ollama-pull.log 2>&1
/usr/local/bin/ollama pull qwen2.5:1.5b >> /tmp/ollama-pull.log 2>&1
OLLAMA_HEALTH=$(curl -s -m 5 http://127.0.0.1:11434/api/tags)
setsid nohup /tmp/cloudflared tunnel --url http://localhost:11434 --no-autoupdate > /tmp/cf-ollama.log 2>&1 &
sleep 45
OLLAMA_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/cf-ollama.log | tail -1)

PORTVIS=$(curl -s -X PATCH -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" -d '{"visibilty":"public"}' "https://api.github.com/user/codespaces/$CODESPACE_NAME/ports/4173" | head -c 300)
{
  echo "tunnel_url: $URL"
  echo "health: $HEALTH"
  echo "ollama_url: $OLLAMA_URL"
  echo "ollama_health: $OLLAMA_HEALTH"
  echo "portvis: $PORTVIS"
  echo "port_url: https://$CODESPACE_NAME-4173.app.github.dev/"
  echo "when: $(date -u)"
} > PUBLIC_URL.txt
{
  echo "ollama_url: $OLLAMA_URL"
  echo "ollama_models: $OLLAMA_HEALTH"
  echo "when: $(date -u)"
} > OLLAMA_URL.txt
git add PUBLIC_URL.txt OLLAMA_URL.txt
git -c user.email=agent@users.noreply.github.com -c user.name=agent commit -m "publish public url + ollama relay" || true
git pull -rebase -X theirs origin main || true
git push || true
