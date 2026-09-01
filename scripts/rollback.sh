#!/bin/bash
# Rollback script for Kubernetes deployments

NAMESPACE="${NAMESPACE:-ecommerce}"
SERVICE="${SERVICE:-}"

log() { echo "[$(date)] $1"; }

rollback() {
    if [ -n "$SERVICE" ]; then
        log "Rolling back $SERVICE..."
        kubectl rollout undo deployment/$SERVICE -n $NAMESPACE
    else
        log "Rolling back all services..."
        for svc in frontend backend payment search; do
            kubectl rollout undo deployment/$svc -n $NAMESPACE
        done
    fi
    kubectl rollout status deployment -n $NAMESPACE --timeout=300s
    kubectl get pods -n $NAMESPACE
}

case "$1" in
    deploy) rollback ;;
    status) kubectl get deployments -n $NAMESPACE ;;
    history) kubectl rollout history deployment/${SERVICE:-frontend} -n $NAMESPACE ;;
    *) echo "Usage: $0 {deploy|status|history} [service]" ;;
esac