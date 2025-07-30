#!/bin/bash

# ==================================================================================
# AUTOMATION STACK - INSTALAÇÃO COMPLETA EM UM COMANDO
# Portainer CE + Evolution API + n8n + Docker
# 
# Desenvolvido por: AI Explorer | Mago das IAS @_blainercosta
# Data: 30/07/2025
# ==================================================================================

set -e  # Para no primeiro erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Função para log com cores
log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ❌ $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] ℹ️  $1${NC}"
}

magic() {
    echo -e "${PURPLE}[$(date +'%H:%M:%S')] 🪄 $1${NC}"
}

# Banner
echo -e "${PURPLE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                        🚀 AUTOMATION STACK INSTALLER                        ║
║                                                                              ║
║                    Portainer CE + Evolution API + n8n                       ║
║                                                                              ║
║                 Desenvolvido por: AI Explorer | Mago das IAS                ║
║                            @_blainercosta                                    ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificar se está rodando como root
if [[ $EUID -eq 0 ]]; then
   error "Este script não deve ser executado como root. Use seu usuário normal."
   exit 1
fi

# Configurações (editáveis)
EVOLUTION_API_KEY=${EVOLUTION_API_KEY:-$(openssl rand -hex 32)}
N8N_PASSWORD=${N8N_PASSWORD:-$(openssl rand -base64 12)}
EXTERNAL_IP=""

# Função para detectar IP externo
get_external_ip() {
    info "Detectando IP externo..."
    EXTERNAL_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s icanhazip.com)
    if [ -z "$EXTERNAL_IP" ]; then
        warn "Não foi possível detectar IP automaticamente."
        echo -n "Digite o IP externo da sua VM: "
        read EXTERNAL_IP
    fi
    log "IP externo detectado: $EXTERNAL_IP"
}

# Função para instalar Docker
install_docker() {
    log "🐳 Instalando Docker..."
    
    # Verificar se Docker já está instalado
    if command -v docker &> /dev/null; then
        log "Docker já está instalado. Pulando..."
        return 0
    fi
    
    # Atualizar sistema
    sudo apt update -qq
    sudo apt upgrade -y -qq
    
    # Instalar Docker
    sudo apt install -y docker.io curl openssl
    
    # Habilitar e iniciar Docker
    sudo systemctl enable docker
    sudo systemctl start docker
    
    # Adicionar usuário ao grupo docker
    sudo usermod -aG docker $USER
    
    log "Docker instalado com sucesso!"
}

# Função para instalar Portainer
install_portainer() {
    log "🌊 Instalando Portainer CE..."
    
    # Verificar se já existe
    if docker ps -a --format "table {{.Names}}" | grep -q "portainer"; then
        warn "Portainer já existe. Removendo versão anterior..."
        docker stop portainer 2>/dev/null || true
        docker rm portainer 2>/dev/null || true
    fi
    
    # Criar volume
    docker volume create portainer_data 2>/dev/null || true
    
    # Executar Portainer
    docker run -d \
        -p 8000:8000 \
        -p 9443:9443 \
        --name portainer \
        --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:lts
    
    log "Portainer instalado! Acesse: https://$EXTERNAL_IP:9443"
}

# Função para instalar Evolution API
install_evolution_api() {
    log "📱 Instalando Evolution API..."
    
    # Verificar se já existe
    if docker ps -a --format "table {{.Names}}" | grep -q "evolution-api"; then
        warn "Evolution API já existe. Removendo versão anterior..."
        docker stop evolution-api 2>/dev/null || true
        docker rm evolution-api 2>/dev/null || true
    fi
    
    # Criar volume para dados
    docker volume create evolution_data 2>/dev/null || true
    
    # Executar Evolution API
    docker run -d \
        --name evolution-api \
        -p 8080:8080 \
        --restart=always \
        -v evolution_data:/evolution/instances \
        -e AUTHENTICATION_API_KEY="$EVOLUTION_API_KEY" \
        -e EVOLUTION_API_BASE_URL="http://$EXTERNAL_IP:8080" \
        -e DATABASE_ENABLED=false \
        -e DATABASE_CONNECTION_URI="" \
        -e DATABASE_CONNECTION_DB_PREFIX_NAME="" \
        -e RABBITMQ_ENABLED=false \
        -e CACHE_REDIS_ENABLED=false \
        -e WEBSOCKET_ENABLED=false \
        atendai/evolution-api:v2.1.1
    
    log "Evolution API instalada! Acesse: http://$EXTERNAL_IP:8080"
    info "API Key: $EVOLUTION_API_KEY"
}

# Função para instalar n8n
install_n8n() {
    log "🔄 Instalando n8n..."
    
    # Verificar se já existe
    if docker ps -a --format "table {{.Names}}" | grep -q "n8n"; then
        warn "n8n já existe. Removendo versão anterior..."
        docker stop n8n 2>/dev/null || true
        docker rm n8n 2>/dev/null || true
    fi
    
    # Criar volume para dados
    docker volume create n8n_data 2>/dev/null || true
    
    # Executar n8n
    docker run -d \
        --name n8n \
        -p 5678:5678 \
        --restart=always \
        -v n8n_data:/home/node/.n8n \
        -e N8N_BASIC_AUTH_ACTIVE=true \
        -e N8N_BASIC_AUTH_USER=admin \
        -e N8N_BASIC_AUTH_PASSWORD="$N8N_PASSWORD" \
        -e WEBHOOK_URL="http://$EXTERNAL_IP:5678/" \
        -e N8N_HOST="0.0.0.0" \
        -e N8N_PORT=5678 \
        -e N8N_PROTOCOL=http \
        n8nio/n8n:latest
    
    log "n8n instalado! Acesse: http://$EXTERNAL_IP:5678"
    info "Usuário: admin | Senha: $N8N_PASSWORD"
}

# Função para configurar firewall (se ufw estiver ativo)
configure_firewall() {
    log "🔥 Configurando firewall..."
    
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        sudo ufw allow 8080/tcp comment "Evolution API"
        sudo ufw allow 5678/tcp comment "n8n"
        sudo ufw allow 9443/tcp comment "Portainer HTTPS"
        sudo ufw allow 8000/tcp comment "Portainer Edge"
        log "Regras de firewall configuradas!"
    else
        info "UFW não está ativo. Certifique-se de que as portas estão liberadas no Google Cloud."
    fi
}

# Função para criar arquivo de configuração
create_config_file() {
    log "📝 Criando arquivo de configuração..."
    
    cat > ~/automation-stack-config.txt << EOF
==================================================================================
AUTOMATION STACK - CONFIGURAÇÕES
Desenvolvido por: AI Explorer | Mago das IAS @_blainercosta
Data da instalação: $(date)
==================================================================================

🌐 IP EXTERNO: $EXTERNAL_IP

🌊 PORTAINER CE:
   URL: https://$EXTERNAL_IP:9443
   Usuário: admin (definir na primeira configuração)

📱 EVOLUTION API:
   URL: http://$EXTERNAL_IP:8080
   API Key: $EVOLUTION_API_KEY
   
   Criar instância WhatsApp:
   POST http://$EXTERNAL_IP:8080/instance/create
   Headers: apikey: $EVOLUTION_API_KEY
   Body: {"instanceName": "minha-instancia"}

🔄 N8N:
   URL: http://$EXTERNAL_IP:5678
   Usuário: admin
   Senha: $N8N_PASSWORD

🔗 INTEGRAÇÃO BÁSICA:
   Webhook n8n: http://$EXTERNAL_IP:5678/webhook/whatsapp
   
   Configurar webhook Evolution:
   POST http://$EXTERNAL_IP:8080/webhook/set/minha-instancia
   Body: {"url": "http://$EXTERNAL_IP:5678/webhook/whatsapp"}

🐳 DOCKER CONTAINERS:
   portainer - Gerenciamento visual
   evolution-api - API WhatsApp
   n8n - Automação workflows

📋 COMANDOS ÚTEIS:
   Ver containers: docker ps
   Logs Evolution: docker logs evolution-api
   Logs n8n: docker logs n8n
   Logs Portainer: docker logs portainer
   
   Parar tudo: docker stop portainer evolution-api n8n
   Iniciar tudo: docker start portainer evolution-api n8n

🔧 TROUBLESHOOTING:
   Container não inicia: docker logs NOME_CONTAINER
   Limpar sistema: docker system prune -f
   Reiniciar container: docker restart NOME_CONTAINER

==================================================================================
BACKUP DOS DADOS:
   docker run --rm -v portainer_data:/portainer -v evolution_data:/evolution -v n8n_data:/n8n -v \$(pwd):/backup ubuntu tar czf /backup/automation-backup-\$(date +%Y%m%d).tar.gz /portainer /evolution /n8n

RESTORE DOS DADOS:
   docker run --rm -v portainer_data:/portainer -v evolution_data:/evolution -v n8n_data:/n8n -v \$(pwd):/backup ubuntu tar xzf /backup/automation-backup-YYYYMMDD.tar.gz

==================================================================================
EOF

    log "Arquivo de configuração salvo em: ~/automation-stack-config.txt"
}

# Função para verificar saúde dos containers
check_containers_health() {
    log "🏥 Verificando saúde dos containers..."
    
    sleep 10  # Aguardar containers iniciarem
    
    containers=("portainer" "evolution-api" "n8n")
    
    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep "$container" | grep -q "Up"; then
            log "✅ $container está rodando"
        else
            error "❌ $container não está rodando"
            warn "Log do $container:"
            docker logs --tail 10 "$container" 2>&1 || true
        fi
    done
}

# Função para mostrar resumo final
show_summary() {
    magic "🎉 INSTALAÇÃO CONCLUÍDA!"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                        🚀 ACESSE SEUS SERVIÇOS                  ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  🌊 Portainer:     https://$EXTERNAL_IP:9443                    ║${NC}"
    echo -e "${GREEN}║  📱 Evolution API: http://$EXTERNAL_IP:8080                     ║${NC}"
    echo -e "${GREEN}║  🔄 n8n:           http://$EXTERNAL_IP:5678                     ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  📝 Configurações salvas em: ~/automation-stack-config.txt      ║${NC}"
    echo -e "${GREEN}║  🔑 Evolution API Key: ${EVOLUTION_API_KEY:0:20}...                     ║${NC}"
    echo -e "${GREEN}║  🔒 n8n Password: $N8N_PASSWORD                                  ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    magic "Desenvolvido por: AI Explorer | Mago das IAS @_blainercosta"
    echo ""
    info "Próximos passos:"
    echo "1. Configure o Portainer acessando https://$EXTERNAL_IP:9443"
    echo "2. Crie uma instância do WhatsApp na Evolution API"
    echo "3. Configure seus workflows no n8n"
    echo "4. Leia o arquivo ~/automation-stack-config.txt para mais detalhes"
    echo ""
    warn "IMPORTANTE: Configure as regras de firewall no Google Cloud para as portas 8080, 5678 e 9443"
}

# Função principal
main() {
    info "Iniciando instalação da Automation Stack..."
    
    get_external_ip
    install_docker
    
    # Aplicar mudanças do grupo docker
    if ! groups $USER | grep -q docker; then
        warn "Aplicando mudanças do grupo docker..."
        exec sg docker "$0 --continue"
    fi
    
    install_portainer
    install_evolution_api
    install_n8n
    configure_firewall
    create_config_file
    check_containers_health
    show_summary
}

# Verificar se é continuação após mudança de grupo
if [[ "$1" == "--continue" ]]; then
    shift
    install_portainer
    install_evolution_api
    install_n8n
    configure_firewall
    create_config_file
    check_containers_health
    show_summary
else
    main "$@"
fi
