#!/usr/bin/env bash
# Despliega en EKS la imagen que Actions publicó en GHCR para un commit.
# Uso: ./demo/deploy.sh <sha>     (por defecto, HEAD). El SHA completo de 40 caracteres.
# Requiere: AWS_PROFILE con acceso a cluster-test y el paquete GHCR público.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
SHA="$(git rev-parse "${1:-HEAD}")"
REPO="$(git remote get-url origin | sed -E 's#.*github.com[:/](.*)#\1#; s#\.git$##' | tr '[:upper:]' '[:lower:]')"
IMAGE="ghcr.io/${REPO}:${SHA}"
CLUSTER="${CLUSTER_NAME:-cluster-test}"
REGION="${AWS_REGION:-us-east-1}"

aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null
kubectl apply -f k8s/private-nodes.yaml
sed "s|IMAGE_PLACEHOLDER|${IMAGE}|" k8s/shop.yaml | kubectl apply -f -
echo "Esperando nodo y pod (Auto Mode crea el nodo bajo demanda, 2 a 4 min)..."
kubectl -n shop rollout status deployment/shop --timeout=600s

# El NLB es interno: se verifica desde dentro del pod
GOT="$(kubectl -n shop exec deploy/shop -- wget -qO- http://localhost:3000/version)"
echo "Pod responde: ${GOT}"
echo "$GOT" | grep -q "$SHA" || { echo "El pod no ejecuta ${SHA}" >&2; exit 1; }
echo "NLB interno: $(kubectl -n shop get svc shop -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
