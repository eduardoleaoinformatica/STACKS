#!/bin/bash
set -e

# === CONFIGURAÇÕES ===
EMAIL_SSL="leaoservtech@gmail.com"
DOMAIN_TRAEFIK="traefik.leaosecurity.com.br"
DOMAIN_PORTAINER="portainer.leaosecurity.com.br"
DOMAIN_MINIO_CONSOLE="minio.leaosecurity.com.br"
DOMAIN_MINIO_API="s3storage.leaosecurity.com.br"
DOMAIN_CHATWOOT="chatwoot.leaosecurity.com.br"
DOMAIN_N8N="n8n.leaosecurity.com.br"

POSTGRES_USER="postgres"
POSTGRES_PASSWORD="4zFQKkp1ALZ"
POSTGRES_DB="chatwoot_production"
REDIS_PASSWORD="rk81wJJxBQ13"
MINIO_USER="administrator"
MINIO_PASS="AmtKnieawQ1e"

# === INSTALAÇÃO DO DOCKER ===
echo "[1/5] Instalando Docker e dependências..."
apt update -y >/dev/null
apt install -y ca-certificates curl gnupg lsb-release >/dev/null

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

apt update -y >/dev/null
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null

systemctl enable docker
systemctl start docker

# === CRIAÇÃO DAS PASTAS ===
mkdir -p /opt/stack
cd /opt/stack

# === CRIAR DOCKER COMPOSE ===
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
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=SuperSenhaN8N
      - N8N_ENCRYPTION_KEY=ChaveSeguraN8N
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

networks:
  stacknet:
    driver: bridge

volumes:
  portainer_data:
  postgres_data:
  minio_data:
  n8n_data:
EOF

# === INICIAR STACK ===
echo "[2/5] Subindo containers..."
docker compose up -d

echo "[3/5] Verificando serviços..."
sleep 10
docker ps

echo "[4/5] Instalando finalizado com sucesso!"
echo "----------------------------------------------------"
echo "🌐 Traefik:     https://${DOMAIN_TRAEFIK}"
echo "🌐 Portainer:   https://${DOMAIN_PORTAINER}"
echo "🌐 MinIO:       https://${DOMAIN_MINIO_CONSOLE}"
echo "🌐 Chatwoot:    https://${DOMAIN_CHATWOOT}"
echo "🌐 n8n:         https://${DOMAIN_N8N}"
echo "----------------------------------------------------"
echo "✅ Todos os serviços estão sendo gerenciados via Traefik com SSL automático."
