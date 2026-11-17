#!/usr/bin/env bash
# Despliega en EKS la imagen que Actions publicó en GHCR para un commit.
# Uso: ./demo/deploy.sh <sha>     (por defecto, HEAD)
# Requiere: AWS_PROFILE con acceso a cluster-test, y el paquete GHCR en modo público.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
SHA="${1:-$(git rev-parse HEAD)}"
REPO="$(git remote get-url origin | sed -E 's#.*github.com[:/](.*)#\1#; s#\.git$##' | tr '[:upper:]' '[:lower:]')"
IMAGE="ghcr.io/${REPO}:${SHA}"
CLUSTER="${CLUSTER_NAME:-cluster-test}"
REGION="${AWS_REGION:-us-east-1}"

aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null
sed "s|IMAGE_PLACEHOLDER|${IMAGE}|" k8s/shop.yaml | kubectl apply -f -
kubectl -n shop rollout status deployment/shop --timeout=180s

echo "Esperando el endpoint público..."
for i in $(seq 1 40); do
  HOST=$(kubectl -n shop get svc shop -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  if [ -n "$HOST" ] && curl -fsS "http://$HOST/version" 2>/dev/null | grep -q "$SHA"; then
    echo "Staging ejecuta ${SHA}: http://$HOST"
    echo "Si es la primera vez, guarda esta URL como variable de GitHub STAGING_URL."
    exit 0
  fi
  sleep 15
done
echo "El endpoint no devolvió ${SHA} a tiempo" >&2
exit 1
