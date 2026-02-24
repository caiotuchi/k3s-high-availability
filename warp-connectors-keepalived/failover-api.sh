#!/bin/bash

# Carregar variáveis de configuração
source /etc/keepalived/api-credentials.conf

# Log para depuração
echo "Script failover-api.sh chamado em $(date)" | tee -a /var/log/failover.log

# Função para atualizar a rota via PATCH
update_route() {
    local route_id=$1
    local tunnel_id=$2

    echo "Tentando PATCH para route_id=$route_id, tunnel_id=$tunnel_id" | tee -a /var/log/failover.log
    RESPONSE=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/teamnet/routes/$route_id" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"tunnel_id\": \"$tunnel_id\", \"network\": \"$SUBNET\", \"comment\": \"Failover to $tunnel_id at $(date)\"}")

    if echo "$RESPONSE" | jq -r '.success' | grep -q "true"; then
        echo "Rota atualizada para túnel $tunnel_id em $(date)" | tee -a /var/log/failover.log
    else
        ERROR=$(echo "$RESPONSE" | jq -r '.errors[] // "Sem detalhes de erro"')
        echo "Erro ao atualizar rota com Bearer token: $ERROR" | tee -a /var/log/failover.log
        # Fallback para X-Auth-Email e X-Auth-Key
        echo "Tentando PATCH com X-Auth-Email/X-Auth-Key..." | tee -a /var/log/failover.log
        RESPONSE=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/teamnet/routes/$route_id" \
            -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
            -H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
            -H "Content-Type: application/json" \
            --data "{\"tunnel_id\": \"$tunnel_id\", \"network\": \"$SUBNET\", \"comment\": \"Failover to $tunnel_id at $(date)\"}")
        if echo "$RESPONSE" | jq -r '.success' | grep -q "true"; then
            echo "Rota atualizada com X-Auth-Email/X-Auth-Key para túnel $tunnel_id em $(date)" | tee -a /var/log/failover.log
        else
            ERROR=$(echo "$RESPONSE" | jq -r '.errors[] // "Sem detalhes de erro"')
            echo "Erro ao atualizar rota com X-Auth-Email/X-Auth-Key: $ERROR" | tee -a /var/log/failover.log
        fi
    fi
}

# Verifica se WARP está conectado e se este servidor é o MASTER (tem o VIP)
echo "Verificando WARP e VIP..." | tee -a /var/log/failover.log
WARP_STATUS=$(/usr/bin/warp-cli status | grep Connected || echo "WARP não conectado")
VIP_STATUS=$(ip addr show | grep "$VIP" || echo "VIP $VIP não encontrado")
echo "WARP_STATUS: $WARP_STATUS" | tee -a /var/log/failover.log
echo "VIP_STATUS: $VIP_STATUS" | tee -a /var/log/failover.log

if [ "$WARP_STATUS" = "Status update: Connected" ] && [ "$VIP_STATUS" != "VIP $VIP não encontrado" ]; then
    # Somente se for MASTER: Buscar detalhes da rota
    echo "Servidor é MASTER (VIP presente). Buscando detalhes da rota $ROUTE_ID para $SUBNET..." | tee -a /var/log/failover.log
    CURRENT_ROUTE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/teamnet/routes/$ROUTE_ID" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json")

    CURRENT_TUNNEL_ID=$(echo "$CURRENT_ROUTE" | jq -r '.result.tunnel_id')
    ROUTE_NETWORK=$(echo "$CURRENT_ROUTE" | jq -r '.result.network')

    echo "CURRENT_TUNNEL_ID=$CURRENT_TUNNEL_ID, ROUTE_NETWORK=$ROUTE_NETWORK" | tee -a /var/log/failover.log
    if [ "$ROUTE_NETWORK" = "$SUBNET" ] && [ "$CURRENT_TUNNEL_ID" != "$TUNNEL_ID_LOCAL" ]; then
        echo "Rota atual está em $CURRENT_TUNNEL_ID, atualizando para $TUNNEL_ID_LOCAL..." | tee -a /var/log/failover.log
        update_route "$ROUTE_ID" "$TUNNEL_ID_LOCAL"
    else
        echo "Rota já está correta ($TUNNEL_ID_LOCAL) ou não corresponde à sub-rede $SUBNET em $(date)." | tee -a /var/log/failover.log
    fi
else
    echo "Servidor não é MASTER (VIP ausente) ou WARP não conectado. Nenhuma ação realizada em $(date)." | tee -a /var/log/failover.log
    exit 0
fi