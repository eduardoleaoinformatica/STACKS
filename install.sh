#!/bin/bash
set -e

echo "🚀 Iniciando instalação da stack de produção..."

# -----------------------------
# CONFIGURAÇÃO DE DOMÍNIOS E SENHAS
# -----------------------------
read -p "🌐 Dominio Traefik (ex: traefik.leaosecurity.com.br): " DOMAIN_TRAEFIK
read -p "🌐 Dominio Portainer (ex: portainer.leaosecurity.com.br): " DOMAIN_PORTAINER
read -p "🌐 Dominio MinIO Console (ex: minio.leaosecurity.com.br): " DOMAIN_MINIO_CONSOLE
read -p "🌐 Dominio MinIO API (ex: s3storage.leaosecurity.com.br): " DOMAIN_MINIO_API
read -p "🌐 Dominio Chatwoot (ex: chatwoot.leaosecurity.com.br): " DOMAIN_CHATWOOT
read -p "🌐 Dominio n8n (ex: n8n.leaosecurity.com.br): " DOMAIN_N8N
read -p "📧 Email para SSL Let's Encrypt: " EMAIL_SSL

# Senhas seguras (você pode alterar se quiser)
POSTGRES_USER="postgres"
POSTGRES_PASSWORD="4zFQKkp1ALZ"
POSTGRES_DB="chatwoot_production"
REDIS_PASSWORD="rk81wJJxBQ13"
MINIO_USER="administrator"
MINIO_PASS="AmtKnieawQ1e"
N8N_USER="eduardo"
N8N_PASS="37954149897Eduardo"
N8N_KEY=$(openssl rand -hex 16)

STACK_DIR="/opt/stack"

# -----------------------------
# 1️⃣ INSTALAR DOCKER + COMPOSE
# -----------------------------
echo "[1/6] Instalando Docker e dependências..."
apt update -y >/dev/null
apt install -y ca-certificates curl gnupg lsb-release openssl >/dev/null

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

apt update -y >/dev/null
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null

systemctl enable docker
systemctl start docker

# -----------------------------
# 2️⃣ CRIAR DIRETÓRIOS E REDE
# -----------------------------
echo "[2/6] Criando pastas e rede..."
mkdir -p ${STACK_DIR}/{portainer_data,postgres_data,minio_data,n8n_data,letsencrypt}
cd ${STACK_DIR}

if ! docker network ls | grep -q stacknet; then
  docker network create stacknet
fi

# -----------------------------
# 3️⃣ CRIAR DOCKER-COMPOSE
# -----------------------------
echo "[3/6] Gerando docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: "3.8"

services:
  traefik:
    image: traefik:latest
    container_name: traefik
    restart: always
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --entrypoints.web.http.redirections.entryPoint.to=websecure
      - --entrypoints.web.http.redirections.entryPoint.scheme=https
      - --certificatesresolvers.leresolver.acme.httpchallenge=true
      - --certificatesresolvers.leresolver.acme.httpchallenge.entrypoint=web
      - --certificatesresolvers.leresolver.acme.email=${EMAIL_SSL}
      - --certificatesresolvers.leresolver.acme.storage=/letsencrypt/acme.json
      - --api.dashboard=true
      - --log.level=INFO
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./letsencrypt:/letsencrypt
    networks:
      - stacknet
    labels:
      - traefik.enable=true
      - traefik.http.routers.traefik.rule=Host(\`${DOMAIN_TRAEFIK}\`)
      - traefik.http.routers.traefik.entrypoints=websecure
      - traefik.http.routers.traefik.tls.certresolver=leresolver
      - traefik.http.routers.traefik.service=api@internal

  portainer:
    image: portainer/portainer-ce:latest
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./portainer_data:/data
    networks:
      - stacknet
    labels:
      - traefik.enable=true
      - traefik.http.routers.portainer.rule=Host(\`${DOMAIN_PORTAINER}\`)
      - traefik.http.routers.portainer.entrypoints=websecure
      - traefik.http.routers.portainer.tls.certresolver=leresolver
      - traefik.http.services.portainer.loadbalancer.server.port=9000

  postgres:
    image: postgres:15
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - ./postgres_data:/var/lib/postgresql/data
    networks:
      - stacknet

  redis:
    image: redis:7
    command: redis-server --requirepass ${REDIS_PASSWORD}
    restart: always
    networks:
      - stacknet

  minio:
    image: quay.io/minio/minio
    command: server /data --console-address ":9001"
    restart: always
    environment:
      MINIO_ROOT_USER: ${MINIO_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_PASS}
    volumes:
      - ./minio_data:/data
    networks:
      - stacknet
    labels:
      - traefik.enable=true
      - traefik.http.routers.minio_api.rule=Host(\`${DOMAIN_MINIO_API}\`)
      - traefik.http.routers.minio_api.entrypoints=websecure
      - traefik.http.routers.minio_api.tls.certresolver=leresolver
      - traefik.http.services.minio_api.loadbalancer.server.port=9000
      - traefik.http.routers.minio_console.rule=Host(\`${DOMAIN_MINIO_CONSOLE}\`)
      - traefik.http.routers.minio_console.entrypoints=websecure
      - traefik.http.routers.minio_console.tls.certresolver=leresolver
      - traefik.http.services.minio_console.loadbalancer.server.port=9001

  n8n:
    image: n8nio/n8n:latest
    restart: always
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASS}
      - N8N_ENCRYPTION_KEY=${N8N_KEY}
      - EXECUTIONS_PROCESS=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - DB_POSTGRESDB_DATABASE=n8n
    depends_on:
      - redis
      - postgres
    volumes:
      - ./n8n_data:/home/node/.n8n
    networks:
      - stacknet
    labels:
      - traefik.enable=true
      - traefik.http.routers.n8n.rule=Host(\`${DOMAIN_N8N}\`)
      - traefik.http.routers.n8n.entrypoints=websecure
      - traefik.http.routers.n8n.tls.certresolver=leresolver
      - traefik.http.services.n8n.loadbalancer.server.port=5678

  chatwoot:
    image: chatwoot/chatwoot:latest
    restart: always
    environment:
      - RAILS_ENV=production
      - POSTGRES_HOST=postgres
      - POSTGRES_USERNAME=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DATABASE=${POSTGRES_DB}
      - REDIS_URL=redis://default:${REDIS_PASSWORD}@redis:6379
      - MINIO_ENABLED=true
      - MINIO_ENDPOINT=minio:9000
      - MINIO_BUCKET=chatwoot
      - MINIO_ACCESS_KEY=${MINIO_USER}
      - MINIO_SECRET_KEY=${MINIO_PASS}
    depends_on:
      - postgres
      - redis
      - minio
    networks:
      - stacknet
    labels:
      - traefik.enable=true
      - traefik.http.routers.chatwoot.rule=Host(\`${DOMAIN_CHATWOOT}\`)
      - traefik.http.routers.chatwoot.entrypoints=websecure
      - traefik.http.routers.chatwoot.tls.certresolver=leresolver
      - traefik.http.services.chatwoot.loadbalancer.server.port=3000

  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: always
    command: --interval 300 --cleanup
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - stacknet

networks:
  stacknet:
    driver: bridge

volumes:
  portainer_data:
  postgres_data:
  minio_data:
  n8n_data:
  letsencrypt:
EOF

# -----------------------------
# 4️⃣ SUBIR CONTAINERS
# -----------------------------
echo "[4/6] Subindo containers..."
docker compose up -d

# -----------------------------
# 5️⃣ AGUARDAR INICIALIZAÇÃO
# -----------------------------
echo "[5/6] Aguardando inicialização dos serviços..."
sleep 20
docker ps

# -----------------------------
# 6️⃣ MENSAGEM FINAL
# -----------------------------
echo "[6/6] Stack de produção instalada com sucesso!"
echo "----------------------------------------------------"
echo "🌐 Traefik:     https://${DOMAIN_TRAEFIK}"
echo "🌐 Portainer:   https://${DOMAIN_PORTAINER}"
echo "🌐 MinIO:       https://${DOMAIN_MINIO_CONSOLE}"
echo "🌐 Chatwoot:    https://${DOMAIN_CHATWOOT}"
echo "🌐 n8n:         https://${DOMAIN_N8N}"
echo "----------------------------------------------------"
echo "✅ Todos os containers estão monitorados pelo Watchtower a cada 5 minutos."
echo "💡 Certificados SSL gerados automaticamente via Let's Encrypt."
