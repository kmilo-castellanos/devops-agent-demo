#!/usr/bin/env bash
# Opcional (bloque GA): rompe el deployment para que DevOps Agent investigue.
# Después pide en el chat: "Investigate why deployment shop in namespace shop is not ready"
set -euo pipefail
kubectl -n shop set image deployment/shop shop=public.ecr.aws/docker/library/node:does-not-exist
kubectl -n shop get pods
echo "Restaurar: kubectl -n shop rollout undo deployment/shop"
