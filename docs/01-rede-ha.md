# Rede HA entre Clusters com Cloudflare WARP Connector e Keepalived

## Objetivo
- Conectar sub-redes distintas via Cloudflare WARP Connector
- Prover IP virtual por site com Keepalived (VRRP) para alta disponibilidade
- Base Debian 12 (Bookworm) em 4 VMs (2 por site)

## Topologia
- Cluster A: VM-A1 e VM-A2 (Keepalived + WARP), VIP: <VIP_CLUSTER_A_WARP>
- Cluster B: VM-B1 e VM-B2 (Keepalived + WARP), VIP: <VIP_CLUSTER_B_WARP>
- Tráfego inter-cluster encapsulado na rede global Cloudflare

## Pré-requisitos
- Debian 12 atualizado
- Acesso sudo
- Interfaces de rede com IPs estáticos por VM

### Configurar Hosts em /etc/hosts de todas as maquinas
```bash
# Hosts do Cluster A 
<IP_CLUSTER_A_MASTER01> ca-master-01
<IP_CLUSTER_A_MASTER02> ca-master-02
<IP_CLUSTER_A_MASTER03> ca-master-03
<IP_CLUSTER_A_WORKER01> ca-worker-01
<IP_CLUSTER_A_WORKER02> ca-worker-02
<IP_CLUSTER_A_WORKER03> ca-worker-03
<IP_CLUSTER_A_WARP_CONNECTOR_A1> ca-warp-connector-01
<IP_CLUSTER_A_WARP_CONNECTOR_A2> ca-warp-connector-02
<VIP_CLUSTER_A_KUBEAPI> ca-kube-apiserver-vip
<VIP_CLUSTER_A_WARP> ca-warp-connector-vip
# Hosts do Cluster B
<IP_CLUSTER_B_MASTER01> cb-master-01
<IP_CLUSTER_B_MASTER02> cb-master-02
<IP_CLUSTER_B_MASTER03> cb-master-03
<IP_CLUSTER_B_WORKER01> cb-worker-01
<IP_CLUSTER_B_WORKER02> cb-worker-02
<IP_CLUSTER_B_WORKER03> cb-worker-03
<IP_CLUSTER_B_WARP_CONNECTOR_A1> cb-warp-connector-01
<IP_CLUSTER_B_WARP_CONNECTOR_A2> cb-warp-connector-02
<VIP_CLUSTER_B_KUBEAPI> cb-kube-apiserver-vip
<VIP_CLUSTER_B_WARP> cb-warp-connector-vip
```

### Atualização inicial

```bash
sudo apt update
sudo apt -y upgrade
sudo reboot
```

## Instalação do Cloudflare WARP Connector
- Repositório oficial Cloudflare
- Serviço warp-svc com warp-cli

```bash
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-warp.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp.gpg] https://pkg.cloudflareclient.com/ bookworm main" | sudo tee /etc/apt/sources.list.d/cloudflare-warp.list
sudo apt update
sudo apt -y install cloudflare-warp

sudo systemctl enable warp-svc
sudo systemctl start warp-svc

warp-cli register
warp-cli set-mode warp
warp-cli connect
warp-cli status
```

## Instalação do Keepalived (VRRP)

```bash
sudo apt -y install keepalived
```

### Script de checagem do WARP
- Usado para influenciar prioridade VRRP

```bash
sudo tee /usr/local/bin/check-warp.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
warp-cli status | grep -qi "Connected"
EOF
sudo chmod +x /usr/local/bin/check-warp.sh
```

### Configuração Keepalived (exemplo Cluster A)
- Ajustar interface, VIP e peers

```bash
sudo tee /etc/keepalived/keepalived.conf >/dev/null <<'EOF'
vrrp_script chk_warp {
    script "/usr/local/bin/check-warp.sh"
    interval 5
    weight 10
}

vrrp_instance VI_A {
    state BACKUP
    interface <IFACE_SITE_A>
    virtual_router_id 11
    priority 100
    advert_int 1
    unicast_peer {
        <IP_VM_A1>
        <IP_VM_A2>
    }
    authentication {
        auth_type PASS
        auth_pass <SENHA_SITE_A>
    }
    track_script {
        chk_warp
    }
    virtual_ipaddress {
        <VIP_SITE_A>/32 dev <IFACE_SITE_A>
    }
}
EOF
```

### Configuração Keepalived (exemplo Cluster B)

```bash
sudo tee /etc/keepalived/keepalived.conf >/dev/null <<'EOF'
vrrp_script chk_warp {
    script "/usr/local/bin/check-warp.sh"
    interval 5
    weight 10
}

vrrp_instance VI_B {
    state BACKUP
    interface <IFACE_SITE_B>
    virtual_router_id 22
    priority 100
    advert_int 1
    unicast_peer {
        <IP_VM_B1>
        <IP_VM_B2>
    }
    authentication {
        auth_type PASS
        auth_pass <SENHA_SITE_B>
    }
    track_script {
        chk_warp
    }
    virtual_ipaddress {
        <VIP_SITE_B>/32 dev <IFACE_SITE_B>
    }
}
EOF
```

### Ativação e verificação

```bash
sudo systemctl enable keepalived
sudo systemctl restart keepalived
sudo systemctl status keepalived --no-pager
ip addr show <IFACE_CLUSTER_A>
ip addr show <IFACE_CLUSTER_B>
```

## Testes de Conectividade
- Ping VIPs entre clusters pelo túnel Cloudflare

```bash
ping -c 4 <VIP_CLUSTER_A>
ping -c 4 <VIP_CLUSTER_B>
```

## Considerações
- Garantir rotas e firewall permitindo tráfego entre VIPs
- Manter faixas de pods/serviços dos clusters sem sobreposição

