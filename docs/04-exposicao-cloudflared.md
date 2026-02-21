# Exposição Segura da API REST via Cloudflare Tunnel (cloudflared)

## Objetivo
- Publicar a API REST do TCC de forma segura
- Usar Cloudflare Tunnel com cloudflared como Deployment

## Pré-requisitos
- Conta Cloudflare e Tunnel criado
- Credenciais do Tunnel (`credentials.json`) ou token
- Domínio configurado em Cloudflare

## Namespace

```bash
kubectl create namespace tcc-edge
```

## Secret com credenciais
- Método 1: credentials.json

```bash
kubectl -n tcc-edge create secret generic cloudflared-credentials \
  --from-file=credentials.json=./credentials.json
```

## ConfigMap de ingress
- Ajuste host e serviço/porta internos

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloudflared-config
  namespace: tcc-edge
data:
  config.yaml: |
    tunnel: "<TUNNEL_ID>"
    credentials-file: /etc/cloudflared/credentials.json
    ingress:
      - hostname: api.tcc.example.com
        service: http://tcc-api.tcc.svc.cluster.local:8080
      - service: http_status:404
```

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloudflared-config
  namespace: tcc-edge
data:
  config.yaml: |
    tunnel: "<TUNNEL_ID>"
    credentials-file: /etc/cloudflared/credentials.json
    ingress:
      - hostname: api.tcc.example.com
        service: http://tcc-api.tcc.svc.cluster.local:8080
      - service: http_status:404
EOF
```

## Deployment cloudflared
- Executa `tunnel run` com config

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: tcc-edge
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cloudflared
  template:
    metadata:
      labels:
        app: cloudflared
    spec:
      containers:
        - name: cloudflared
          image: cloudflare/cloudflared:2025.2.1
          args:
            - tunnel
            - --config
            - /etc/cloudflared/config.yaml
            - run
          volumeMounts:
            - name: creds
              mountPath: /etc/cloudflared/credentials.json
              subPath: credentials.json
            - name: cfg
              mountPath: /etc/cloudflared/config.yaml
              subPath: config.yaml
      volumes:
        - name: creds
          secret:
            secretName: cloudflared-credentials
        - name: cfg
          configMap:
            name: cloudflared-config
```

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: tcc-edge
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cloudflared
  template:
    metadata:
      labels:
        app: cloudflared
    spec:
      containers:
        - name: cloudflared
          image: cloudflare/cloudflared:2025.2.1
          args:
            - tunnel
            - --config
            - /etc/cloudflared/config.yaml
            - run
          volumeMounts:
            - name: creds
              mountPath: /etc/cloudflared/credentials.json
              subPath: credentials.json
            - name: cfg
              mountPath: /etc/cloudflared/config.yaml
              subPath: config.yaml
      volumes:
        - name: creds
          secret:
            secretName: cloudflared-credentials
        - name: cfg
          configMap:
            name: cloudflared-config
EOF
```

## Verificação

```bash
kubectl -n tcc-edge get deploy,pods
kubectl -n tcc-edge logs deploy/cloudflared --tail=100
```

## Notas
- Alternativamente, usar `--token <TUNNEL_TOKEN>` sem credentials-file
- Proteger o namespace com NetworkPolicies conforme requisitos

