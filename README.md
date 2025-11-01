## ⚠️ Pré-requisitos

Você deve criar os subdominios do tipo 'A' na Cloudflare
*Status do Proxy deve esta desligado

<p>portainer</p>
<p>www.portainer</p>
<p>traefik</p>
<p>www.traefik</p>
<p>minio</p>
<p>www.minio</p>
<p>n8n</p>
<p>www.n8n</p>
<p>chatwoot</p>
<p>www.chatwoot</p>
<p>s3storage</p>
<p>www.s3storage</p>



## Gerar uma senha no link abaixo para o traefik

<a href="https://packtypebot.com.br/gerador/htpasswd.php">Gerador de Senha htpasswd</a>

## 💽 Instalação

<p>Copie e cole no Terminal da sua VPS:</p>

```
sudo apt update && sudo apt install -y git && git clone https://github.com/eduardoleaoinformatica/stacks.git && cd stacks && sudo chmod +x install.sh && ./install.sh
```

<p> e siga o passo a passo</p>

## Caso  instância do Portainer expire

Abra o terminal e rode os seguintes comandos:

<p>cd Portainer

<p>docker compose down --remove-orphans
<p>docker compose pull portainer
<p>docker compose up -d

## ❤️ Creditos

<p>Eu e o ChatGPeto... kkk</p>
