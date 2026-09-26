# Kubernetes learning deployment

AWS ECS Fargate is the maintained cloud target. These manifests provide a working Kubernetes learning path for a cluster with the Nginx Ingress Controller installed.

Build and publish the seven images first, then apply everything with:

```bash
kubectl apply -k infrastructure/k8s
kubectl rollout status deployment --all -n ecommerce --timeout=300s
kubectl get pods,services,ingress -n ecommerce
```

The image references use the public GHCR path and the `latest` convenience tag. For a repeatable exercise, replace every tag with the same immutable commit SHA before applying. If the package is private, configure an `imagePullSecret` in the `ecommerce` namespace.

The product service uses its embedded demo catalog in Kubernetes. The persistent DynamoDB integration and IAM task role are configured by the supported AWS ECS Terraform deployment.
