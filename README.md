# Projeto de Kubernetes Multi-cluster HA com K3s, Cilium e Cloudflare

Este repositório contém a documentação e os manifestos para a criação de um ambiente Kubernetes multi-cluster de alta disponibilidade, projetado para fins acadêmicos e de pesquisa. A arquitetura utiliza K3s, Cilium com ClusterMesh, Kube-VIP para o plano de controle e Cloudflare Tunnels para exposição segura de serviços.

## Visão Geral da Arquitetura

O ambiente é composto por dois clusters Kubernetes (Cluster A e Cluster B) geograficamente distribuídos, operando em modo de alta disponibilidade.

- **Distribuição Kubernetes**: K3s `v1.28.9+k3s1` com `etcd` embutido, otimizado para leveza e performance.
- **Alta Disponibilidade (Control Plane)**: Kube-VIP em modo `Static Pod` para fornecer um Virtual IP (VIP) para o `kube-apiserver`, garantindo a resiliência do plano de controle em cada cluster.
- **Rede CNI**: Cilium `v1.15.5` com suporte a IPv6, utilizando `kube-proxy replacement` para otimização de performance e observabilidade com Hubble.
- **Conectividade Multi-Cluster**: Cilium ClusterMesh para conectar os dois clusters, permitindo a descoberta de serviços e políticas de rede unificadas entre eles.
- **Exposição de Serviços**: Cloudflare Tunnel (`cloudflared`) implantado como um `Deployment` para expor serviços de forma segura à internet, sem a necessidade de IPs públicos ou configurações complexas de firewall.
- **Sistema Operacional**: Debian 12 (Bookworm) como base para todos os nós.

## Diagrama do Multi-cluster

![Diagrama de Arquitetura](Diagrama.png)

## Aplicação Exemplo: Arquitetura e HA

Para validar a arquitetura, foi utilizada uma aplicação de exemplo que consiste em:

- **Frontend**: Uma interface web desenvolvida em React.
- **Backend**: Uma API RESTful em Python (Flask) que se conecta ao banco de dados.
- **Banco de Dados**: PostgreSQL configurado com replicação assíncrona:
  - **Cluster A**: Contém a instância primária (master) do PostgreSQL, responsável pelas operações de escrita.
  - **Cluster B**: Contém réplicas (standby) que sincronizam os dados do master.
- **Failover**: Um sistema de failover (não detalhado neste README) é responsável por promover uma réplica em caso de falha do master.

Os manifestos para esta aplicação estão localizados em `manifests/example-app/`.

## Estrutura do Repositório

```
.
├── docs/
│   ├── 01-rede-ha.md
│   ├── 02-control-plane.md
│   ├── 03-cilium-mesh.md
│   └── 04-exposicao-cloudflared.md
├── manifests/
│   └── example-app/
│       ├── 01-postgres-master.yaml
│       ├── 02-postgres-replicas-c1.yaml
│       ├── ... (outros manifestos)
├── README.md
└── Diagrama.png
```

- **docs/**: Contém os guias passo a passo para configurar cada componente da arquitetura.
- **manifests/**: Armazena os manifestos Kubernetes para a aplicação de exemplo e outros componentes.
- **README.md**: Este arquivo, com a visão geral do projeto.
- **Diagrama.png**: Diagrama visual da arquitetura.

## Sumário de Guias

Cada guia abaixo é um documento autocontido que detalha a implementação de uma parte específica da arquitetura.

- **[01-rede-ha.md](docs/01-rede-ha.md)**: (WIP) Descreve a configuração da rede WAN entre os sites, utilizando Cloudflare WARP e Keepalived para garantir a conectividade resiliente.
- **[02-control-plane.md](docs/02-control-plane.md)**: Detalha a instalação do K3s e a configuração da alta disponibilidade do plano de controle com Kube-VIP.
- **[03-cilium-mesh.md](docs/03-cilium-mesh.md)**: Cobre a instalação do Cilium, configuração do ClusterMesh para conectar os dois clusters e testes de conectividade.
- **[04-exposicao-cloudflared.md](docs/04-exposicao-cloudflared.md)**: Explica como implantar a aplicação de exemplo e expô-la de forma segura usando o Cloudflare Tunnel.

## Objetivo do Projeto

Este projeto foi desenvolvido com os seguintes objetivos principais:

- **Reprodutibilidade Acadêmica**: Prover uma documentação determinística e detalhada, permitindo que outros pesquisadores e estudantes reproduzam a arquitetura em seus próprios ambientes. Cada guia inclui comandos reais e verificações para garantir que cada etapa foi concluída com sucesso.
- **Modularidade**: A arquitetura é dividida em subsistemas independentes (rede, plano de controle, CNI, exposição), permitindo que cada componente seja estudado, modificado ou substituído isoladamente.
- **Rigor Técnico**: Todas as versões de software são especificadas e testadas. A documentação inclui explicações técnicas sobre as decisões de arquitetura e os comandos utilizados.
- **Aprendizado Prático**: Serve como um laboratório para experimentar conceitos avançados de Kubernetes, como multi-cluster, alta disponibilidade, CNI avançado e exposição segura de serviços.

### Requisitos Mínimos para Reprodução

- **Hardware**: No mínimo 6 máquinas (3 por cluster) para uma configuração básica de alta disponibilidade.
- **Sistema Operacional**: Debian 12 (Bookworm) ou compatível.
- **Conectividade**: Rede entre os clusters para o ClusterMesh e acesso à internet para os repositórios de software e Cloudflare.
- **Contas**: Uma conta no Cloudflare para configurar os Tunnels (plano gratuito é suficiente).