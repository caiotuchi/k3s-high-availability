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
  name: kube-vip
  namespace: kube-system
  labels:
    app.kubernetes.io/name: kube-vip
spec:
  hostNetwork: true
  containers:
    - name: kube-vip
      image: ghcr.io/kube-vip/kube-vip:v0.7.0
      args:
        - manager
      env:
        - name: vip_arp
          value: "true"
        - name: port
          value: "6443"
        - name: vip_interface
          value: "<IFACE_CTRL>"
        - name: vip_subnet
          value: "32"
        - name: cp_enable
          value: "true"
        - name: cp_namespace
          value: "kube-system"
        - name: vip_address
          value: "<VIP_CTRL_PLANE>"
        - name: vip_leaderelection
          value: "true"
      securityContext:
        capabilities:
          add:
            - NET_ADMIN
            - NET_RAW
      imagePullPolicy: IfNotPresent
```

### Instalação do Static Pod em todos os control-plane

```bash
sudo mkdir -p /var/lib/rancher/k3s/agent/pod-manifests
sudo tee /var/lib/rancher/k3s/agent/pod-manifests/kube-vip.yaml >/dev/null <<'EOF'
<COLE AQUI O YAML DO POD>
EOF
```

## Configuração do K3s para Cilium
- Desabilitar Flannel e kube-proxy
- Desabilitar componentes que não serão usados
- Incluir SAN para o VIP
- Habilitar dual-stack (ajuste CIDRs conforme necessidade)

```yaml
# /etc/rancher/k3s/config.yaml
write-kubeconfig-mode: "0644"
tls-san:
  - "<VIP_CTRL_PLANE>"
flannel-backend: "none"
disable-kube-proxy: true
disable-network-policy: true
cluster-init: true
disable:
  - servicelb
  - traefik
cluster-cidr: "10.42.0.0/16,fd00:42::/56"
service-cidr: "10.43.0.0/16,fd00:43::/108"
```

## Inicialização do primeiro servidor (etcd embutido)

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --config /etc/rancher/k3s/config.yaml

sudo systemctl status k3s --no-pager
sudo k3s kubectl get nodes -o wide
```

## Inclusão de servidores adicionais
- Apontar para o endpoint VIP

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --server "https://<VIP_CTRL_PLANE>:6443" \
  --token "<K3S_TOKEN>" \
  --config /etc/rancher/k3s/config.yaml
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

