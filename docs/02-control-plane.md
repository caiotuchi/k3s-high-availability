# Plano de Controle HA com Kube-VIP (Static Pod) e K3s HA

## Objetivo
- Publicar a API Kubernetes em VIP:6443 com Kube-VIP (Static Pod)
- Inicializar K3s v1.28.9+k3s1 em modo HA com etcd embutido
- Preparar K3s para Cilium: flannel=none e desativar kube-proxy

## Pré-requisitos
- VIP: <VIP_CTRL_PLANE>
- Interface de rede: <IFACE_CTRL>
- DNS resolvendo o VIP opcionalmente

## Kube-VIP como Static Pod
- K3s usa por padrão `/var/lib/rancher/k3s/agent/pod-manifests` para pods estáticos
- O pod roda com hostNetwork e anuncia o VIP por ARP

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
      value: <VIP_CLUSTER_A_API>
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
curl -sfL https://get.k3s.io | sh -s - server \
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
  --tls-san ca-master01 \
  --tls-san ca-master02 \
  --tls-san ca-master03

sudo systemctl status k3s --no-pager
sudo k3s kubectl get nodes -o wide
```

## Inclusão de servidores adicionais
- Apontar para o endpoint VIP

### Adicionar mais servidores
```bash
curl -sfL https://get.k3s.io | K3S_TOKEN="<K3S_TOKEN>" sh -s - server \
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
  --tls-san ca-master01 \
  --tls-san ca-master02 \
  --tls-san ca-master03
```
### Adicionar mais agentes

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN="<K3S_TOKEN>" sh -s - agent \
  --server https://ca-kube-apiserver-vip:6443 \
  --node-label "node.kubernetes.io/worker=true"
```
## Verificações

```bash
sudo k3s kubectl -n kube-system get pods -o wide | grep kube-vip
sudo k3s kubectl get nodes -o wide
sudo ss -lntp | grep 6443
```

## Observações
- Em K3s, DaemonSet do Kube-VIP também é suportado
- Static Pod atende ao requisito de VIP disponível antes do cluster completo