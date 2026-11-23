#!/usr/bin/env bash
# D2: simula un commit de configuración que rompe el batch (ruta de entrada inexistente).
# En el siguiente run de cron (máx. 5 min) la instancia descarga la config rota y el job falla.
# Restaurar: ./demo/break-batch-config.sh restore
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
CONF=batch/config/batch.properties
git checkout main

if [ "${1:-}" = "restore" ]; then
  sed -i.bak 's#^input.file=.*#input.file=/opt/batch/data/orders.csv#' "$CONF" && rm -f "$CONF.bak"
  git commit -am "config(batch): restore input path"
else
  sed -i.bak 's#^input.file=.*#input.file=/opt/batch/inbound/orders.csv#' "$CONF" && rm -f "$CONF.bak"
  git commit -am "config(batch): move input to inbound directory"
fi
git push origin main
echo "Listo. El efecto se ve en el siguiente run (cron cada 5 min)."
