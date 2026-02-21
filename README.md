# Ambiente Kubernetes Multi-cluster (K3s) HA com Cilium, IPv6, Kube-VIP e Cloudflare Tunnel

## Visão Geral
- Distribuição: Debian 12 (Bookworm)
- Kubernetes: K3s v1.28.9+k3s1 com etcd embutido
- Alta disponibilidade do plano de controle: Kube-VIP como Static Pod
- Conectividade WAN entre sites: 4 VMs com Cloudflare WARP Connector e Keepalived (2 por site, HA)
- CNI: Cilium v1.15.5 com IPv6, Hubble e ClusterMesh
- Exposição segura de serviços: Cloudflare Tunnel (cloudflared) como Deployment

## Diagrama do Multi-cluster

![Diagrama de Arquitetura](Diagrama.png)

## Sumário de Guias
- Rede HA entre sites: [01-rede-ha.md](file:///d:/k3s-high-availability/docs/01-rede-ha.md)
- Plano de Controle HA (Kube-VIP + K3s): [02-control-plane.md](file:///d:/k3s-high-availability/docs/02-control-plane.md)
- Cilium, IPv6 e ClusterMesh: [03-cilium-mesh.md](file:///d:/k3s-high-availability/docs/03-cilium-mesh.md)
- Exposição segura com cloudflared: [04-exposicao-cloudflared.md](file:///d:/k3s-high-availability/docs/04-exposicao-cloudflared.md)

## Objetivo
- Prover reprodutibilidade acadêmica com passos determinísticos
- Modularidade: cada guia cobre um subsistema
- Estrito ao rigor técnico e versões especificadas

