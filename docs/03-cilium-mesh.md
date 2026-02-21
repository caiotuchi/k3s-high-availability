# Cilium v1.15.5 com IPv6, Hubble e ClusterMesh em K3s

## Objetivo
- Instalar Cilium via Helm com kube-proxy replacement (strict)
- Habilitar IPv6 e Hubble
- Conectar clusters via ClusterMesh com CA compartilhada

## Pré-requisitos
- K3s com flannel=none e kube-proxy desativado
- VIP e porta da API: 6443
- PodCIDR e ServiceCIDR sem sobreposição entre clusters

## Instalação do Helm chart
- Versão do chart: 1.15.5
- Namespace: kube-system

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update
```

### Valores recomendados (ajuste conforme ambiente)

```yaml
# values-cilium.yaml
cluster:
  name: "cluster-a"
  id: 1

ipv4:
  enabled: true
ipv6:
  enabled: true

k8sServiceHost: "<VIP_CTRL_PLANE>"
k8sServicePort: 6443

kubeProxyReplacement: "strict"

hubble:
  relay:
    enabled: true
  ui:
    enabled: true

ipam:
  operator:
    clusterPoolIPv4PodCIDRList:
      - "10.42.0.0/16"
    clusterPoolIPv6PodCIDRList:
      - "fd00:42::/56"

nodePort:
  enabled: true
```

### Instalação

```bash
helm install cilium cilium/cilium \
  --version 1.15.5 \
  --namespace kube-system \
  -f values-cilium.yaml
```

### Verificação

```bash
cilium status --wait
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
```

## Cluster B
- Repita a instalação alterando:
  - cluster.name: "cluster-b"
  - cluster.id: 2
  - CIDRs de pods IPv4/IPv6 que não conflitem

## Habilitar ClusterMesh
- Instalar cilium-cli

```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```

### Compartilhar CA do Cilium
- Copiar o secret `cilium-ca` do Cluster A para o Cluster B

```bash
kubectl --context=$CLUSTER1 get secret -n kube-system cilium-ca -o yaml | \
  kubectl --context $CLUSTER2 create -f -
```

### Ativar componentes de ClusterMesh

```bash
cilium clustermesh enable --context $CLUSTER1
cilium clustermesh enable --context $CLUSTER2
```

### Conectar clusters

```bash
cilium clustermesh connect --context $CLUSTER1 --destination-context $CLUSTER2
```

### Status

```bash
cilium clustermesh status --context $CLUSTER1
cilium clustermesh status --context $CLUSTER2
```

## Observações de Endereçamento
- Ajuste ipv4NativeRoutingCIDR/ipv6-native-routing-cidr quando usar roteamento nativo
- Garanta conectividade entre nós por seus InternalIP

