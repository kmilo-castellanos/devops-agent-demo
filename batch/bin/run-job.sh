#!/usr/bin/env bash
# Ejecuta el job batch. Lo lanza cron cada 5 minutos.
# Antes de correr, sincroniza la configuración desde la rama main del repositorio
# (así un commit de configuración rompe o arregla el siguiente run).
set -u
RAW_BASE="${RAW_BASE:-}"            # p. ej. https://raw.githubusercontent.com/<org>/<repo>/main/batch
CONF=/opt/batch/config/batch.properties
LOG=/var/log/batch/job.log
mkdir -p "$(dirname "$LOG")"

if [ -n "$RAW_BASE" ] && curl -fsS "$RAW_BASE/config/batch.properties" -o "$CONF.new"; then
  mv "$CONF.new" "$CONF"
fi

# Heap acotado, típico de un job antiguo
java -Xmx64m -cp /opt/batch/classes LegacyBatchJob "$CONF" >> "$LOG" 2>&1
RC=$?
if [ $RC -ne 0 ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR [run-job.sh] LegacyBatchJob exited with code $RC" >> "$LOG"
fi
exit $RC
