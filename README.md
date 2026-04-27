# E-Commerce Platform

Production-ready microservices deployment platform.

## Structure
```
ecommerce-deploy/
├── services/           # 8 microservices
│   ├── frontend/       # Frontend service
│   ├── backend/        # API service
│   ├── payment/        # Payment service
│   ├── search/         # Search service
│   ├── cart/           # Cart service
│   ├── product/        # Product catalog
│   ├── api/            # API Gateway
│   └── web/            # Web frontend
├── infrastructure/     # DevOps configs
│   ├── k8s/           # Kubernetes manifests
│   ├── terraform/     # AWS infrastructure
│   └── ansible/       # Server config
├── ci-cd/             # CI/CD pipelines
├── monitoring/        # Prometheus config
├── nginx/             # Reverse proxy
└── scripts/           # Utility scripts
```

## Quick Start
```bash
docker-compose up -d
```

## Deploy to K8s
```bash
kubectl apply -f infrastructure/k8s/base/
kubectl apply -f infrastructure/k8s/frontend/
kubectl apply -f infrastructure/k8s/backend/
```# test
