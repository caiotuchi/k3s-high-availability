# Cilium v1.15.5 com ClusterMesh em K3s

## Objetivo
- Instalar Cilium via Helm com kube-proxy replacement (strict)
- Conectar clusters via ClusterMesh com CA compartilhada

## Pré-requisitos
- K3s v1.28.9+k3s1 com flannel=none e kube-proxy desativado
- Plano de controle HA configurado com Kube-VIP
- VIP e porta da API: 6443 acessível entre clusters
- PodCIDR e ServiceCIDR sem sobreposição entre clusters
- **Hosts configurados**: Entradas no /etc/hosts resolvendo os nós de ambos os clusters
- **Contextos kubectl**: Configurados para ambos os clusters (serão criados durante o processo)

## Instalação do Helm chart
- Versão do chart: 1.15.5 (compatível com K3s v1.28.9)
- Namespace: kube-system
- **Importante**: Execute em ambos os clusters com ajustes de cluster.name e cluster.id

```bash
# Adicionar repositório do Cilium
helm repo add cilium https://helm.cilium.io/
helm repo update

# Verificar versões disponíveis
helm search repo cilium/cilium --versions | head -10
```

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update
```

### Instalação no Cluster A

```bash
# Instalar Cilium com configurações específicas para ClusterMesh
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

# Aguardar Cilium ficar pronto
kubectl -n kube-system rollout status deployment/cilium-operator
kubectl -n kube-system rollout status daemonset/cilium
```

### Configuração de LoadBalancer e L2 Announcements

```bash
# Criar pool de IPs para LoadBalancer e política L2
kubectl apply -f - --context=k3s-cluster-ca <<EOF
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: default-pool
spec:
  blocks:
  - start: "<CLUSTER_A_LOAD_BALANCER_START_IP>"  # Faixa de IPs livres para LoadBalancer do Cluster A
    stop: "<CLUSTER_A_LOAD_BALANCER_END_IP>"
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumL2AnnouncementPolicy
metadata:
  name: clustermesh-l2-policy
spec:
  interfaces:
  - eth0  # Interface de rede principal
  externalIPs: true
  loadBalancerIPs: true
  serviceSelector:
    matchLabels:
      k8s-app: clustermesh-apiserver
EOF

# Reiniciar operator para aplicar mudanças
kubectl rollout restart deployment/cilium-operator -n kube-system
```

### Verificação da instalação

```bash
# Verificar status do Cilium
cilium status --wait

# Verificar pods do Cilium
kubectl -n kube-system get pods -l k8s-app=cilium -o wide

# Verificar saúde do Cilium
kubectl -n kube-system exec daemonset/cilium -- cilium status

# Verificar Hubble
kubectl -n kube-system get pods -l k8s-app=hubble-relay
kubectl -n kube-system get pods -l k8s-app=hubble-ui

# Testar conectividade Cilium
kubectl -n kube-system exec daemonset/cilium -- cilium connectivity test
```

## Instalação no Cluster B

Repita a instalação no Cluster B com as seguintes alterações:

### Configurações para Cluster B:
```bash
# Instalar Cilium no Cluster B com configurações adaptadas
helm upgrade --install cilium cilium/cilium --version 1.15.5 \
  --namespace kube-system \
  --set cluster.name=cluster-b \
  --set cluster.id=2 \
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
  --set ipam.operator.clusterPoolIPv4PodCIDRList[0]=10.101.0.0/16 \
  --set global.mtu=1230

# Configurar pool de IPs diferente para Cluster B
kubectl apply -f - --context=k3s-cluster-cb <<EOF
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: default-pool
spec:
  blocks:
  - start: "<CLUSTER_B_LOAD_BALANCER_START_IP>"  # Faixa de IPs livres para LoadBalancer do Cluster B
    stop: "<CLUSTER_B_LOAD_BALANCER_END_IP>"
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
```

**Importante**: Certifique-se de que os CIDRs não conflitem entre os clusters:
- Cluster A: PodCIDR `10.100.0.0/16`, ServiceCIDR `10.43.0.0/16`
- Cluster B: PodCIDR `10.101.0.0/16`, ServiceCIDR `10.45.0.0/16`

## Instalar cilium-cli

O cilium-cli é essencial para gerenciar o ClusterMesh. Instale a versão compatível:

```bash
# Detectar versão estável mais recente
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
echo "Instalando cilium-cli versão: $CILIUM_CLI_VERSION"

# Detectar arquitetura
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi

# Baixar e instalar
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

# Verificar instalação
cilium version
```

## Preparar contextos kubectl para ambos os clusters

### Criar contexto para Cluster A
No master-01 do Cluster A:
```bash
# Criar arquivo de config com contexto específico
cat /etc/rancher/k3s/k3s.yaml > /root/k3s-cluster-a.yaml
sed -i 's/default/k3s-cluster-a/g' /root/k3s-cluster-a.yaml
sed -i "s/127.0.0.1/ca-kube-apiserver-vip/" /root/k3s-cluster-a.yaml

# Testar contexto
export KUBECONFIG=/root/k3s-cluster-a.yaml
kubectl config current-context  # Deve mostrar: k3s-cluster-a
kubectl get nodes
```

### Criar contexto para Cluster B  
No master-01 do Cluster B:
```bash
# Criar arquivo de config com contexto específico
cat /etc/rancher/k3s/k3s.yaml > /root/k3s-cluster-b.yaml
sed -i 's/default/k3s-cluster-b/g' /root/k3s-cluster-b.yaml
sed -i "s/127.0.0.1/cb-kube-apiserver-vip/" /root/k3s-cluster-b.yaml

# Testar contexto
export KUBECONFIG=/root/k3s-cluster-b.yaml
kubectl config current-context  # Deve mostrar: k3s-cluster-b
kubectl get nodes
```

### Trocar arquivos de configuração entre clusters
No master-01 do Cluster A:
```bash
# Copiar config do Cluster A para Cluster B
scp /root/k3s-cluster-a.yaml root@cb-master-01:/root/k3s-cluster-a.yaml
```

No master-01 do Cluster B:
```bash
# Copiar config do Cluster B para Cluster A
scp /root/k3s-cluster-b.yaml root@ca-master-01:/root/k3s-cluster-b.yaml
```

### Unir configurações em ambos os clusters
No master-01 de ambos os clusters:
```bash
# Criar kubeconfig unificado
KUBECONFIG=/root/k3s-cluster-a.yaml:/root/k3s-cluster-b.yaml kubectl config view --merge --flatten > /root/kubeconfig-merged.yaml

# Exportar para uso
export KUBECONFIG=/root/kubeconfig-merged.yaml

# Verificar contextos disponíveis
kubectl config get-contexts
kubectl get nodes --context=k3s-cluster-a
kubectl get nodes --context=k3s-cluster-b
```

## Configurar ClusterMesh

### Compartilhar certificado CA do Cilium

Para que os clusters se conectem via ClusterMesh, eles devem compartilhar o mesmo certificado CA:

```bash
# No Cluster A, exportar o certificado CA
kubectl get secret -n kube-system cilium-ca -o yaml --context=k3s-cluster-a > cilium-ca.yaml

# No Cluster B, substituir o certificado CA pelo do Cluster A
kubectl delete secret cilium-ca -n kube-system --context=k3s-cluster-b
kubectl apply -f cilium-ca.yaml --context=k3s-cluster-b

# Reiniciar componentes do Cilium no Cluster B
kubectl rollout restart daemonset/cilium -n kube-system --context=k3s-cluster-b
kubectl rollout restart deployment/cilium-operator -n kube-system --context=k3s-cluster-b

# Verificar se os certificados estão iguais
kubectl get secret -n kube-system cilium-ca -o jsonpath='{.data.ca\.crt}' --context=k3s-cluster-a | base64 -d | openssl x509 -noout -text | grep Serial
kubectl get secret -n kube-system cilium-ca -o jsonpath='{.data.ca\.crt}' --context=k3s-cluster-b | base64 -d | openssl x509 -noout -text | grep Serial
```
### Habilitar ClusterMesh nos clusters

```bash
# Habilitar ClusterMesh no Cluster A com LoadBalancer
cilium clustermesh enable --context k3s-cluster-a --service-type=LoadBalancer

# Habilitar ClusterMesh no Cluster B
cilium clustermesh enable --context k3s-cluster-b --service-type=LoadBalancer

# Verificar status antes da conexão
cilium clustermesh status --context k3s-cluster-a --wait
cilium clustermesh status --context k3s-cluster-b --wait
```

### Conectar os clusters

```bash
# Conectar Cluster A ao Cluster B
# Isso estabelece o túnel de comunicação entre os clusters
cilium clustermesh connect --context k3s-cluster-a \
  --destination-context k3s-cluster-b

# Verificar status da conexão
cilium clustermesh status --context k3s-cluster-a --wait
cilium clustermesh status --context k3s-cluster-b --wait

# Testar conectividade entre clusters
cilium clustermesh status --context k3s-cluster-a
cilium clustermesh status --context k3s-cluster-b
```

## Testar conectividade ClusterMesh

### Criar pods de teste em ambos os clusters

```bash
# No Cluster A, criar um pod de teste
kubectl create deployment test-app-a --image=nginx:alpine --replicas=1 --context=k3s-cluster-a
kubectl expose deployment test-app-a --port=80 --type=ClusterIP --context=k3s-cluster-a

# No Cluster B, criar um pod de teste
kubectl create deployment test-app-b --image=nginx:alpine --replicas=1 --type=ClusterIP --context=k3s-cluster-b
kubectl expose deployment test-app-b --port=80 --type=ClusterIP --context=k3s-cluster-b

# Verificar se os serviços estão visíveis entre clusters
kubectl get services --context=k3s-cluster-a --all-namespaces | grep test-app
kubectl get services --context=k3s-cluster-b --all-namespaces | grep test-app
```

### Verificar conectividade final

```bash
# Verificar status detalhado do ClusterMesh
cilium clustermesh status --context k3s-cluster-a
cilium clustermesh status --context k3s-cluster-b

# Listar clusters conectados
cilium clustermesh list --context k3s-cluster-a
cilium clustermesh list --context k3s-cluster-b

# Verificar health do ClusterMesh
kubectl -n kube-system get pods -l k8s-app=clustermesh-apiserver --context=k3s-cluster-a
kubectl -n kube-system get pods -l k8s-app=clustermesh-apiserver --context=k3s-cluster-b
```

## Troubleshooting e Comandos Úteis

### Verificar logs do ClusterMesh
```bash
# Logs do clustermesh-apiserver
kubectl -n kube-system logs -l k8s-app=clustermesh-apiserver --context=k3s-cluster-a
kubectl -n kube-system logs -l k8s-app=clustermesh-apiserver --context=k3s-cluster-b

# Logs do Cilium agent
kubectl -n kube-system logs -l k8s-app=cilium --context=k3s-cluster-a | grep -i cluster
kubectl -n kube-system logs -l k8s-app=cilium --context=k3s-cluster-b | grep -i cluster
```

### Verificar certificados e conectividade
```bash
# Verificar certificados do ClusterMesh
kubectl -n kube-system get secrets | grep clustermesh
kubectl -n kube-system describe secret clustermesh-apiserver-remote-cert --context=k3s-cluster-a

# Testar conectividade entre APIs do ClusterMesh
kubectl -n kube-system get svc clustermesh-apiserver --context=k3s-cluster-a
kubectl -n kube-system get svc clustermesh-apiserver --context=k3s-cluster-b
```

### Limpar e reconfigurar ClusterMesh
```bash
# Se precisar recomeçar, desabilitar ClusterMesh
cilium clustermesh disable --context k3s-cluster-a
cilium clustermesh disable --context k3s-cluster-b

# Limpar recursos relacionados
kubectl -n kube-system delete svc clustermesh-apiserver --context=k3s-cluster-a
kubectl -n kube-system delete svc clustermesh-apiserver --context=k3s-cluster-b
```

### Comandos de diagnóstico
```bash
# Verificar informações de cluster do Cilium
kubectl -n kube-system exec daemonset/cilium -- cilium cluster-info --context=k3s-cluster-a
kubectl -n kube-system exec daemonset/cilium -- cilium cluster-info --context=k3s-cluster-b

# Listar identidades de segurança
kubectl -n kube-system exec daemonset/cilium -- cilium identity list --context=k3s-cluster-a
kubectl -n kube-system exec daemonset/cilium -- cilium identity list --context=k3s-cluster-b

# Verificar políticas de rede
kubectl -n kube-system exec daemonset/cilium -- cilium policy get --context=k3s-cluster-a
kubectl -n kube-system exec daemonset/cilium -- cilium policy get --context=k3s-cluster-b
```

