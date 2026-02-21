# Configuração de Cluster K3s HA com Cilium, IPv6, API REST e HAProxy/Keepalived em VMs Separadas para TCC no Debian 12

Este guia descreve como configurar um cluster K3s de alta disponibilidade (HA) com três nós de control plane (`master01`, `master02`, `master03`) e três nós workers (`worker01`, `worker02`, `worker03`), usando etcd embutido, Cilium como CNI com suporte a IPv6, e garantindo que os nós de control plane executem apenas pods essenciais. O balanceador de carga HAProxy e o Keepalived são configurados em duas VMs separadas (`loadbalancer01` e `loadbalancer02`, com um IP virtual dinâmico resolvido como `api-vip`) para balancear o tráfego da API REST e da API do Kubernetes. O cluster é otimizado para aprendizado e apresentação de um TCC, rodando uma API REST simples, e adaptado para o Debian 12 (Bookworm) com IPs dinâmicos atribuídos via DHCP.

## Pré-requisitos
- **Nós do Cluster**:
  - `master01`: 2 vCPUs, 4 GB RAM
  - `master02`: 2 vCPUs, 4 GB RAM
  - `master03`: 2 vCPUs, 4 GB RAM
  - `worker01`: 1 vCPU, 2 GB RAM
  - `worker02`: 1 vCPU, 2 GB RAM
  - `worker03`: 1 vCPU, 2 GB RAM
- **Nós do Balanceador de Carga**:
  - `loadbalancer01`: 1 vCPU, 1 GB RAM
  - `loadbalancer02`: 1 vCPU, 1 GB RAM
- **IP Virtual**: Resolvido como `api-vip` (definido no Keepalived, por exemplo, um IP dinâmico como `192.168.x.100` dentro da sub-rede atribuída pelo DHCP).
- **Sistema Operacional**: Debian 12 (Bookworm).
- **Conectividade de Rede**:
  - IPs dinâmicos atribuídos via DHCP.
  - Suporte a IPv6 habilitado.
  - Resolução de nomes via `/etc/hosts` ou DNS interno (recomendado).
  - Portas abertas nos nós do cluster: 6443 (API Kubernetes), 2379-2380 (etcd), 8472 (Cilium VXLAN), 4240 (Cilium health check), 80 (API REST).
  - Portas abertas nas VMs LoadBalancer: 80 (API REST), 6443 (API Kubernetes), 54321 (Keepalived VRRP).
- **Acesso root** em todos os nós.
- **Uso**: Cluster para aprendizado e TCC, rodando uma API REST simples com HAProxy e Keepalived.

## Passo 1: Configuração Inicial em Todos os Nós do Cluster

### 1.6 Habilitar IPv6 e anúncios ARP
Edite `/etc/sysctl.conf`:
```bash
nano /etc/sysctl.conf
```

Adicione:
```
net.ipv6.conf.all.disable_ipv6=0
net.ipv6.conf.default.disable_ipv6=0
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.eth0.arp_accept=1
net.ipv4.conf.all.arp_accept=1
```

Aplique:
```bash
sysctl -p
```

## Passo 2: Configuração nas VMs LoadBalancer01 e LoadBalancer02

Configure o HAProxy e o Keepalived **antes** de instalar os nós adicionais do cluster para garantir que o IP virtual (`api-vip`) esteja ativo.

### 2.1 Atualizar o Sistema
Em **loadbalancer01** e **loadbalancer02**:
```bash
apt update
apt upgrade -y
apt install -y curl chrony haproxy keepalived
```

### 2.2 Configurar Hostname
No `loadbalancer01`:
```bash
hostnamectl set-hostname loadbalancer01
```

No `loadbalancer02`:
```bash
hostnamectl set-hostname loadbalancer02
```

### 2.3 Configurar /etc/hosts
Edite `/etc/hosts`:
```bash
nano /etc/hosts
```

Adicione (substitua `<IP_DINAMICO_X>` pelos IPs reais):
```
<IP_DINAMICO_MASTER01> master01
<IP_DINAMICO_MASTER02> master02
<IP_DINAMICO_MASTER03> master03
<IP_DINAMICO_WORKER01> worker01
<IP_DINAMICO_WORKER02> worker02
<IP_DINAMICO_WORKER03> worker03
<IP_DINAMICO_API_VIP> api-vip
<IP_DINAMICO_LOADBALANCER01> loadbalancer01
<IP_DINAMICO_LOADBALANCER02> loadbalancer02
```

### 2.4 Sincronizar Relógio
```bash
systemctl enable --now chrony
timedatectl
```

### 2.5 Configurar Firewall
```bash
apt install -y ufw
ufw allow 80/tcp      # API REST
ufw allow 6443/tcp    # API Kubernetes
ufw allow 54321/udp   # Keepalived VRRP
ufw allow 22/tcp      # SSH
ufw enable
ufw status
```

### 2.6 Configurar Keepalived
Escolha um IP virtual dentro da sub-rede atribuída pelo DHCP (por exemplo, `192.168.x.100`). No **loadbalancer01**, edite `/etc/keepalived/keepalived.conf`:
```bash
nano /etc/keepalived/keepalived.conf
```

Adicione:
```
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 200
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass mysecret
    }
    virtual_ipaddress {
        <IP_DINAMICO_API_VIP>/24  # Exemplo: 192.168.x.100/24
    }
}
```

No **loadbalancer02**, edite `/etc/keepalived/keepalived.conf`:
```bash
nano /etc/keepalived/keepalived.conf
```

Adicione:
```
vrrp_instance VI_1 {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass mysecret
    }
    virtual_ipaddress {
        <IP_DINAMICO_API_VIP>/24  # Exemplo: 192.168.x.100/24
    }
}
```

Habilite e inicie o Keepalived em ambas as VMs:
```bash
systemctl enable keepalived
systemctl start keepalived
```

Verifique o IP virtual no `loadbalancer01`:
```bash
ip addr show
```

Saída esperada:
```
inet <IP_DINAMICO_API_VIP>/24 scope global eth0
```

### 2.7 Configurar HAProxy
Em **loadbalancer01** e **loadbalancer02**, edite `/etc/haproxy/haproxy.cfg`:
```bash
nano /etc/haproxy/haproxy.cfg
```

Substitua o conteúdo por:
```
global
    log /dev/log local0
    maxconn 4096
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend k3s_api_front
    bind <IP_DINAMICO_API_VIP>:6443  # Exemplo: 192.168.x.100:6443
    mode tcp
    default_backend k3s_api_back

backend k3s_api_back
    mode tcp
    balance roundrobin
    server master01 master01:6443 check
    server master02 master02:6443 check
    server master03 master03:6443 check

frontend api_rest_front
    bind <IP_DINAMICO_API_VIP>:80  # Exemplo: 192.168.x.100:80
    mode tcp
    default_backend api_rest_back

backend api_rest_back
    mode tcp
    balance roundrobin
    server worker01 worker01:80 check
    server worker02 worker02:80 check
    server worker03 worker03:80 check
```

Habilite e inicie o HAProxy:
```bash
systemctl enable haproxy
systemctl start haproxy
```

### 2.8 Testar o IP Virtual e o HAProxy
Em qualquer nó ou máquina com acesso à rede, teste a conectividade com o IP virtual:
```bash
ping <IP_DINAMICO_API_VIP>  # Exemplo: ping 192.168.x.100
```

Teste a porta 6443 (API do Kubernetes, após instalar o `master01`):
```bash
telnet <IP_DINAMICO_API_VIP> 6443
```

Se o `telnet` conectar, o HAProxy e o Keepalived estão funcionando. Caso contrário, verifique os logs:
```bash
journalctl -u haproxy.service
journalctl -u keepalived.service
```

## Passo 3: Instalar K3s no Master01
No `master01`:
```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.28.9+k3s1 sh -s - server \
  --cluster-init \
  --disable-network-policy \
  --disable traefik \
  --flannel-backend=none \
  --disable=kube-proxy \
  --disable=servicelb \
  --node-taint CriticalAddonsOnly=true:NoExecute \
  --tls-san <IP_DINAMICO_API_VIP> \
  --tls-san master01 \
  --tls-san master02 \
  --tls-san master03
```

Verifique:
```bash
systemctl status k3s.service
```

Obtenha o token:
```bash
cat /var/lib/rancher/k3s/server/node-token
```

Teste o IP virtual para a API do Kubernetes:
```bash
curl -k https://<IP_DINAMICO_API_VIP>:6443/version
```

## Passo 4: Configurar o Kubeconfig
No `master01`:
```bash
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
chown root:root ~/.kube/config
sed -i "s/127.0.0.1/<IP_DINAMICO_API_VIP>/" ~/.kube/config
```

Teste:
```bash
kubectl get nodes
```

Saída esperada:
```
NAME       STATUS   ROLES                       AGE   VERSION
master01   Ready    control-plane,etcd,master   5m    v1.28.9+k3s1
```

## Passo 5: Instalar K3s no Master02 e Master03

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.28.9+k3s1 K3S_TOKEN=<TOKEN> sh -s - server \
  --server https://<IP_DINAMICO_API_VIP>:6443 \
  --disable-network-policy \
  --disable traefik \
  --flannel-backend=none \
  --disable=kube-proxy \
  --disable=servicelb \
  --node-taint CriticalAddonsOnly=true:NoExecute \
  --tls-san <IP_DINAMICO_API_VIP> \
  --tls-san master01 \
  --tls-san master02 \
  --tls-san master03
```

Substitua `<TOKEN>` pelo token do `master01`.

## Passo 6: Instalar Cilium no Cluster
No `master01`:

1. Instale o Helm:
   ```bash
   curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
   chmod 700 get_helm.sh
   ./get_helm.sh
   ```

2. Adicione o repositório do Cilium:
   ```bash
   helm repo add cilium https://helm.cilium.io/
   helm repo update
   ```

3. Instale o Cilium:
   ```bash
     helm install cilium cilium/cilium --version 1.15.5 \
      --namespace kube-system \
      --set ipam.mode=cluster-pool \
      --set ipv6.enabled=true \
      --set cluster.name=k3s-cluster-01 \
      --set cluster.id=1 \
      --set hubble.enabled=true \
      --set hubble.relay.enabled=true \
      --set hubble.ui.enabled=true \
      --set ingressController.enabled=true \
      --set ingressController.loadBalancerMode=shared \
      --set ingressController.default=true \
      --set clustermesh.enabled=true \
      --set clustermesh.useApiserver=true \
      --set healthChecking=true \
      --set healthPort=9879 \
      --set proxy.connectTimeout=10s \
      --set proxy.responseTimeout=30s \
      --set loadBalancer.algorithm=maglev \
      --set endpointHealthChecking.enabled=true \
      --set kubeProxyReplacement=strict \
      --set bpf.hostReachableServices=true
   ```

Verifique:
```bash
kubectl get pods -n kube-system
```

## Passo 7: Instalar MetalLB para LoadBalancer
Para suportar --service-type=LoadBalancer em bare-metal, instale o MetalLB em cada cluster.
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
```
Arquivo 1: metallb-pool.yaml cria o poll de IPs (ex.: 10.20.20.200-10.20.20.250, em caso de multicluster Você precisa dividir sua faixa 10.20.20.200-10.20.20.250 em duas partes, uma para cada cluster exe.: Cluster 01: 10.20.20.200-10.20.20.225 e Cluster 02: 10.20.20.226-10.20.20.250):
```bash
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.20.20.200-10.20.20.250
```
Arquivo 2: metallb-l2.yaml (Isso define como anunciar os IPs daquele pool)
```bash
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2
  namespace: metallb-system
spec:
  # Diz a este anúncio para usar o pool que criamos acima
  ipAddressPools:
  - default-pool
```
Aplique o ConfigMap
```bash
kubectl apply -f metallb-pool.yaml
kubectl apply -f metallb-l2.yaml
```

## Passo 8: Instalar K3s nos Nós Workers
Nos nós `worker01`, `worker02` e `worker03`:
```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.28.9+k3s1 K3S_TOKEN=<TOKEN> sh -s - agent \
  --server https://<IP_DINAMICO_API_VIP>:6443 \
  --node-label "node.kubernetes.io/worker=true"
```

Verifique:
```bash
systemctl status k3s-agent.service
```

## Passo 9: Verificar o Cluster
No `master01`:
```bash
kubectl get nodes
```

Saída esperada:
```
NAME       STATUS   ROLES                       AGE   VERSION
master01   Ready    control-plane,etcd,master   15m   v1.28.9+k3s1
master02   Ready    control-plane,etcd,master   10m   v1.28.9+k3s1
master03   Ready    control-plane,etcd,master   8m    v1.28.9+k3s1
worker01   Ready    worker                      5m    v1.28.9+k3s1
worker02   Ready    worker                      4m    v1.28.9+k3s1
worker03   Ready    worker                      3m    v1.28.9+k3s1
```

Verifique os pods:
```bash
kubectl get pods -n kube-system
```

## Passo 10: Implantar uma API REST Simples
Crie `api-rest-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-rest
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-rest
  template:
    metadata:
      labels:
        app: api-rest
    spec:
      nodeSelector:
        node.kubernetes.io/worker: "true"
      containers:
      - name: api-rest
        image: hashicorp/http-echo
        args: ["-text=Hello from K3s TCC API"]
        ports:
        - containerPort: 5678
        resources:
          requests:
            cpu: "100m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "128Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: api-rest-service
  namespace: default
spec:
  selector:
    app: api-rest
  ports:
    - protocol: TCP
      port: 80
      targetPort: 5678
  type: ClusterIP
```

Aplique:
```bash
kubectl apply -f api-rest-deployment.yaml
```

Obtenha o IP do serviço:
```bash
kubectl get svc api-rest-service
```

## Passo 11: Testar a API REST e a API do Kubernetes
Teste a API REST via IP virtual:
```bash
curl http://<IP_DINAMICO_API_VIP>
```

Saída esperada: `Hello from K3s TCC API`.

Teste a API do Kubernetes via IP virtual:
```bash
curl -k https://<IP_DINAMICO_API_VIP>:6443/version
```

Teste o failover do Keepalived:
1. No `loadbalancer01`, pare o Keepalived:
   ```bash
   systemctl stop keepalived
   ```
2. Verifique no `loadbalancer02` que o IP virtual foi assumido:
   ```bash
   ip addr show
   ```
3. Teste novamente:
   ```bash
   curl http://<IP_DINAMICO_API_VIP>
   ```

## Passo 12: Multi-cluster criando contextos
No master01 do cluster 1:
```bash
cat /etc/rancher/k3s/k3s.yaml > /root/k3s-cluster-01.yaml
sed -i 's/default/k3s-cluster01/g' /root/k3s-cluster-01.yaml
sed -i "s/127.0.0.1/c01-api-vip/" /root/k3s-cluster-01.yaml
```
No master01 do cluster 2:
```bash
cat /etc/rancher/k3s/k3s.yaml > /root/k3s-cluster-02.yaml
sed -i 's/default/k3s-cluster02/g' /root/k3s-cluster-02.yaml
sed -i "s/127.0.0.1/c02-api-vip/" /root/k3s-cluster-02.yaml
```
### Trocando arquivos entre os custers:
No master01 do cluster 1:
```bash
scp /root/k3s-cluster-01.yaml root@c02-master01:/root/k3s-cluster-01.yaml
```
No master01 do cluster 2:
```bash
scp /root/k3s-cluster-02.yaml root@c01-master01:/root/k3s-cluster-02.yaml
```
### Unindo os arquivos de kubeapi dos custers:
No master01 de ambos os clusters:
```bash
KUBECONFIG=/root/k3s-cluster-01.yaml:/root/k3s-cluster-02.yaml kubectl config view --merge --flatten > /root/kubeconfig-merged.yaml
export KUBECONFIG=/root/kubeconfig-merged.yaml
```
Testando contextos em ambos os clusters:
```bash
kubectl config get-contexts
kubectl get nodes --context=k3s-cluster01
kubectl get nodes --context=k3s-cluster02
```

## Passo 12: Multi-cluster Cilium compartilhando o mesmo secret
```bash
kubectl get secret -n kube-system cilium-ca -o yaml --context=k3s-cluster01 > cilium-ca.yaml
kubectl delete secret cilium-ca -n kube-system --context=k3s-cluster02
kubectl apply -f cilium-ca.yaml --context=k3s-cluster02
kubectl rollout restart daemonset/cilium -n kube-system --context=k3s-cluster02
kubectl rollout restart deployment/cilium-operator -n kube-system --context=k3s-cluster02
```
## Passo 12: Multi-cluster unindo clusters com clustermesh do cilium
```bash
cilium clustermesh enable --context k3s-cluster01 --service-type=LoadBalancer
cilium clustermesh enable --context k3s-cluster02 --service-type=LoadBalancer
```
### Unindo os custers:
```bash
# Conexão 01 -> 02
cilium clustermesh connect --context k3s-cluster01 \
  --destination-context k3s-cluster02

# Conexão 02 -> 01
cilium clustermesh connect --context k3s-cluster02 \
  --destination-context k3s-cluster01

cilium clustermesh status --context k3s-cluster01 --wait
cilium clustermesh status --context k3s-cluster02 --wait
```

## Passo 12: Testar Conectividade IPv6
```bash
kubectl get pods -o wide
kubectl exec -it <POD_NAME> -- ping6 -c 4 <OUTRO_POD_IPV6>
```

Use o Hubble:
```bash
cilium hubble observe
```

## Passo 13: Desinstalação
Nos nós Master:
```bash
/usr/local/bin/k3s-uninstall.sh
rm -rf /var/lib/rancher/k3s
rm -rf /etc/rancher/k3s
rm -rf /var/lib/containerd
reboot
```

Nos nós Worker:
```bash
/usr/local/bin/k3s-agent-uninstall.sh
rm -rf /var/lib/rancher/k3s
rm -rf /etc/rancher/k3s
rm -rf /var/lib/containerd
reboot
```

Nas VMs LoadBalancer:
```bash
systemctl stop haproxy keepalived
apt remove -y haproxy keepalived
rm -rf /etc/haproxy /etc/keepalived
reboot
```

## Passo 14: Dicas de Resolução de Problemas
- **Erro ao Conectar com `--server https://<IP_DINAMICO_API_VIP>:6443`**:
  - Verifique o Keepalived:
    ```bash
    ip addr show
    journalctl -u keepalived.service
    ```
  - Verifique o HAProxy:
    ```bash
    journalctl -u haproxy.service
    ```
  - Teste a conectividade:
    ```bash
    ping <IP_DINAMICO_API_VIP>
    telnet <IP_DINAMICO_API_VIP> 6443
    ```
  - Solução: Reinicie o HAProxy e Keepalived ou reconfigure os arquivos `/etc/haproxy/haproxy.cfg` e `/etc/keepalived/keepalived.conf`.

- **Serviço K3s-Agent Não Inicia**:
  - Verifique:
    ```bash
    journalctl -u k3s-agent.service -b
    ```
  - Solução: Confirme o rótulo `node.kubernetes.io/worker=true` e reinstale.

- **Erro de Conectividade**:
  - Teste:
    ```bash
    ping <IP_DINAMICO_API_VIP>
    telnet <IP_DINAMICO_API_VIP> 6443
    telnet <IP_DINAMICO_API_VIP> 80
    ```
  - Solução: Verifique o `ufw`, `/etc/hosts`, HAProxy e Keepalived.

- **Erro de Cilium**:
  - Verifique:
    ```bash
    kubectl logs -n kube-system -l k8s-app=cilium
    ```
  - Solução: Reinstale com `helm upgrade`.

- **Erro de API (503)**:
  - Teste:
    ```bash
    curl -k https://<IP_DINAMICO_API_VIP>:6443
    ```
  - Solução: Reinicie o HAProxy ou reinstale o K3s.

- **Backup**: Faça backup de `/var/lib/rancher/k3s/server`.

## Notas
- **Recursos**: 4 GB/2 vCPUs para servers, 2 GB/1 vCPU para workers, e 1 GB/1 vCPU para load balancers são ideais para o TCC.
- **Ordem de Configuração**: Configurar o HAProxy e Keepalived antes dos nós adicionais evita problemas com o IP virtual.
- **Apresentação**: Mostre `kubectl get nodes`, `kubectl get pods -o wide`, `curl http://<IP_DINAMICO_API_VIP>`, e `cilium hubble observe` para destacar HA, IPv6 e observabilidade. Demonstre o failover parando o Keepalived no `loadbalancer01`.
- **IPs Dinâmicos**: Certifique-se de atualizar `/etc/hosts` ou configurar um DNS interno para resolver os hostnames. Use `ip addr show` para verificar os IPs atribuídos.