# Plano de Controle HA com Kube-VIP (Static Pod) e K3s HA

## Objetivo
- Publicar a API Kubernetes em VIP:6443 com Kube-VIP (Static Pod)
- Inicializar K3s v1.28.9+k3s1 em modo HA com etcd embutido
- Preparar K3s para Cilium: flannel=none e desativar kube-proxy

## Pré-requisitos
- **VIP do plano de controle**: `ca-kube-apiserver-vip` (para Cluster A) ou `cb-kube-apiserver-vip` (para Cluster B)
- **Interface de rede**: `eth0` (ou ajuste conforme seu ambiente)
- **Hosts configurados**: Entradas no /etc/hosts resolvendo os nomes dos nós
- **K3s v1.28.9+k3s1**: Versão específica para compatibilidade com Cilium
- **Cilium pronto**: Aguardando instalação após configuração do plano de controle

## Kube-VIP como Static Pod
- K3s usa por padrão `/var/lib/rancher/k3s/agent/pod-manifests` para pods estáticos
- O pod roda com hostNetwork e anuncia o VIP por ARP
- **Importante**: Substitua `<VIP_CLUSTER_A_API>` pelo IP real do VIP do Cluster A (ex: `10.220.0.10`)

```yaml
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  name: kube-vip
  namespace: kube-system
spec:
  containers:
  - args:
    - manager
    env:
    - name: vip_arp
      value: "true"
    - name: port
      value: "6443"
    - name: vip_interface
      value: "eth0"
    - name: vip_cidr
      value: "32"
    - name: cp_enable
      value: "true"
    - name: cp_namespace
      value: "kube-system"
    - name: vip_ddns
      value: "false"
    - name: svc_enable
      value: "true"
    - name: vip_leaderelection
      value: "true"
    - name: vip_lease
      value: "5"
    - name: vip_leaseduration
      value: "5"
    - name: vip_renewdeadline
      value: "3"
    - name: vip_retryperiod
      value: "1"
    # --- IP Dedicado de VIP para a kube-apiserver ---
    - name: address
      value: "<VIP_CLUSTER_A_API>"  # Ex: 10.220.0.10 para Cluster A
    # ----------------------------------
    - name: prometheus_server
      value: ":2112"
    - name: KUBECONFIG
      value: "/etc/kubernetes/admin.conf"
    image: ghcr.io/kube-vip/kube-vip:v0.8.0
    imagePullPolicy: IfNotPresent
    name: kube-vip
    resources: {}
    securityContext:
      capabilities:
        add:
        - NET_ADMIN
        - NET_RAW
      sysctls:
      - name: net.ipv4.conf.all.arp_ignore
        value: "1"
      - name: net.ipv4.conf.all.arp_announce
        value: "2"
    volumeMounts:
    - mountPath: /etc/kubernetes/admin.conf
      name: kubeconfig
      readOnly: true
  hostNetwork: true
  hostAliases:
  - ip: "127.0.0.1"
    hostnames:
    - "kubernetes"
  volumes:
  - hostPath:
      path: /etc/rancher/k3s/k3s.yaml
      type: File
    name: kubeconfig
  tolerations:
  - key: "CriticalAddonsOnly"
    operator: "Exists"
    effect: "NoExecute"
status: {}
```

## Configuração do K3s para Cilium
- Desabilitar Flannel e kube-proxy
- Desabilitar componentes que não serão usados
- Incluir SAN para o VIP
- Habilitar dual-stack (ajuste CIDRs conforme necessidade)

## Inicialização do primeiro servidor (etcd embutido)

```bash
# Instalar K3s v1.28.9+k3s1 específico
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.28.9+k3s1 sh -s - server \
  --cluster-init \
  --cluster-cidr=10.42.0.0/16 \
  --service-cidr=10.43.0.0/16 \
  --disable-network-policy \
  --disable traefik \
  --flannel-backend=none \
  --disable=kube-proxy \
  --disable=servicelb \
  --node-taint CriticalAddonsOnly=true:NoExecute \
  --tls-san ca-kube-apiserver-vip \
  --tls-san ca-master-01 \
  --tls-san ca-master-02 \
  --tls-san ca-master-03

# Verificar status e logs
sudo systemctl status k3s --no-pager
sudo journalctl -u k3s -f
sudo k3s kubectl get nodes -o wide
```

## Inclusão de servidores adicionais
- Apontar para o endpoint VIP
- **Importante**: Obtenha o token do primeiro servidor antes de prosseguir

### Obter o token do cluster
```bash
# No primeiro servidor (ca-master-01)
sudo cat /var/lib/rancher/k3s/server/node-token
# Copie este token para usar nos próximos comandos
```

### Adicionar mais servidores (ca-master-02, ca-master-03)
```bash
# Instalar K3s nos servidores adicionais
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.28.9+k3s1 K3S_TOKEN="<K3S_TOKEN>" sh -s - server \
  --server https://ca-kube-apiserver-vip:6443 \
  --cluster-cidr=10.42.0.0/16 \
  --service-cidr=10.43.0.0/16 \
  --disable-network-policy \
  --disable traefik \
  --flannel-backend=none \
  --disable=kube-proxy \
  --disable=servicelb \
  --node-taint CriticalAddonsOnly=true:NoExecute \
  --tls-san ca-kube-apiserver-vip \
  --tls-san ca-master-01 \
  --tls-san ca-master-02 \
  --tls-san ca-master-03

# Verificar status
sudo systemctl status k3s --no-pager
sudo k3s kubectl get nodes -o wide
```
### Adicionar mais agentes (ca-worker-01, ca-worker-02, ca-worker-03)

```bash
# Instalar K3s nos workers
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.28.9+k3s1 K3S_TOKEN="<K3S_TOKEN>" sh -s - agent \
  --server https://ca-kube-apiserver-vip:6443 \
  --node-label "node.kubernetes.io/worker=true"

# Verificar status
sudo systemctl status k3s-agent --no-pager
sudo k3s kubectl get nodes -o wide
```
## Verificações

```bash
# Verificar se o Kube-VIP está rodando
sudo k3s kubectl -n kube-system get pods -o wide | grep kube-vip

# Verificar status dos nós
sudo k3s kubectl get nodes -o wide

# Verificar se a API está escutando no VIP
sudo ss -lntp | grep 6443

# Verificar logs do Kube-VIP
sudo k3s kubectl -n kube-system logs -l app.kubernetes.io/name=kube-vip

# Testar conectividade com o VIP
```

## Configuração para o Cluster B

O processo para o Cluster B é análogo, mas com as seguintes adaptações:

1. **Kube-VIP**: Substitua `<VIP_CLUSTER_A_API>` pelo VIP do Cluster B (ex: `10.221.0.10`)
2. **Nomes dos hosts**: Use `cb-master-01`, `cb-master-02`, `cb-master-03` e `cb-kube-apiserver-vip`
3. **CIDRs**: Considere usar faixas diferentes para evitar conflitos (ex: `10.44.0.0/16` e `10.45.0.0/16`)

### Comandos adaptados para Cluster B:
```bash
# Exemplo para o primeiro servidor do Cluster B
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.28.9+k3s1 sh -s - server \
  --cluster-init \
  --cluster-cidr=10.44.0.0/16 \
  --service-cidr=10.45.0.0/16 \
  --disable-network-policy \
  --disable traefik \
  --flannel-backend=none \
  --disable=kube-proxy \
  --disable=servicelb \
  --node-taint CriticalAddonsOnly=true:NoExecute \
  --tls-san cb-kube-apiserver-vip \
  --tls-san cb-master-01 \
  --tls-san cb-master-02 \
  --tls-san cb-master-03
```

## Observações
- Em K3s, DaemonSet do Kube-VIP também é suportado
- Static Pod atende ao requisito de VIP disponível antes do cluster completo

## Comandos Úteis para Troubleshooting

```bash
# Verificar se o Kube-VIP está escutando no VIP
sudo netstat -tulpn | grep 6443

# Verificar logs detalhados do K3s
sudo journalctl -u k3s -n 100 --no-pager

# Verificar configuração do Kube-VIP
sudo cat /var/lib/rancher/k3s/agent/pod-manifests/kube-vip.yaml

# Testar conectividade entre nós
ping -c 4 ca-master-02
ping -c 4 ca-master-03

# Verificar se o VIP está respondendo
curl -k https://ca-kube-apiserver-vip:6443/version

# Verificar status do etcd embutido
sudo k3s etcd-snapshot list
```