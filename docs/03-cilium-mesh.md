# Cilium v1.15.5 com ClusterMesh em K3s

## Objetivo
- Instalar Cilium via Helm com kube-proxy replacement (strict)
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

### Instalação

```bash
helm upgrade --install cilium cilium/cilium --version 1.15.5 \
  --namespace kube-system \
  --set cluster.name=cluster-a \
  --set cluster.id=1 \
  --set ipam.mode=cluster-pool \
  --set kubeProxyReplacement=strict \
  --set bpf.hostReachableServices=true \
  --set healthChecking=true \
  --set healthPort=9879 \
  --set endpointHealthChecking.enabled=true \
  --set proxy.connectTimeout=5s \
  --set proxy.responseTimeout=10s \
  --set loadBalancer.algorithm=random \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set clustermesh.useApiserver=true \
  --set clustermesh.cacheTTL=15s \
  --set l2announcements.enabled=true \
  --set externalIPs.enabled=true \
  --set k8sClientRateLimit.qps=50 \
  --set k8sClientRateLimit.burst=100 \
  --set ipam.operator.clusterPoolIPv4PodCIDRList[0]=10.100.0.0/16 \
  --set global.mtu=1230
```

### Verificação

```bash
kubectl apply -f - --context=k3s-cluster-ca <<EOF
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: default-pool
spec:
  blocks:
  - start: "10.220.0.200"
    stop: "10.220.0.250"
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumL2AnnouncementPolicy
metadata:
  name: clustermesh-l2-policy
spec:
  interfaces:
  - eth0
  externalIPs: true
  loadBalancerIPs: true
  serviceSelector:
    matchLabels:
      k8s-app: clustermesh-apiserver
EOF

kubectl rollout restart deployment/cilium-operator -n kube-system
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

## Iniciando o Multi-cluster

### Criando contextos
No master01 do cluster A:
```bash
cat /etc/rancher/k3s/k3s.yaml > /root/k3s-cluster-a.yaml
sed -i 's/default/k3s-cluster-a/g' /root/k3s-cluster-a.yaml
sed -i "s/127.0.0.1/ca-kube-apiserver-vip/" /root/k3s-cluster-a.yaml
```
No master01 do cluster B:
```bash
cat /etc/rancher/k3s/k3s.yaml > /root/k3s-cluster-b.yaml
sed -i 's/default/k3s-cluster-b/g' /root/k3s-cluster-b.yaml
sed -i "s/127.0.0.1/cb-kube-apiserver-vip/" /root/k3s-cluster-b.yaml
```
### Trocando arquivos entre os custers:
No master01 do cluster A:
```bash
scp /root/k3s-cluster-a.yaml root@cb-master01:/root/k3s-cluster-a.yaml
```
No master01 do cluster B:
```bash
scp /root/k3s-cluster-b.yaml root@ca-master01:/root/k3s-cluster-b.yaml
```
### Unindo os arquivos de kubeapi dos custers:
No master01 de ambos os clusters:
```bash
KUBECONFIG=/root/k3s-cluster-a.yaml:/root/k3s-cluster-b.yaml kubectl config view --merge --flatten > /root/kubeconfig-merged.yaml
export KUBECONFIG=/root/kubeconfig-merged.yaml
```
Testando contextos em ambos os clusters:
```bash
kubectl config get-contexts
kubectl get nodes --context=k3s-cluster-a
kubectl get nodes --context=k3s-cluster-b
```

### Compartilhar CA do Cilium
```bash
kubectl get secret -n kube-system cilium-ca -o yaml --context=k3s-cluster-a > cilium-ca.yaml
kubectl delete secret cilium-ca -n kube-system --context=k3s-cluster-b
kubectl apply -f cilium-ca.yaml --context=k3s-cluster-b
kubectl rollout restart daemonset/cilium -n kube-system --context=k3s-cluster-b
kubectl rollout restart deployment/cilium-operator -n kube-system --context=k3s-cluster-b
```
### Unindo os clusters com clustermesh do cilium
```bash
cilium clustermesh enable --context k3s-cluster-a --service-type=LoadBalancer
cilium clustermesh enable --context k3s-cluster-b --service-type=LoadBalancer
```

```bash
# Conexão 01 -> 02
cilium clustermesh connect --context k3s-cluster-a \
  --destination-context k3s-cluster-b

cilium clustermesh status --context k3s-cluster-a --wait
cilium clustermesh status --context k3s-cluster-b --wait
```

## Observações de Endereçamento
- Ajuste ipv4NativeRoutingCIDR/ipv6-native-routing-cidr quando usar roteamento nativo
- Garanta conectividade entre nós por seus InternalIP

