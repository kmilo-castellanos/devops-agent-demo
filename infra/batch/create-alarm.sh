#!/usr/bin/env bash
# Crea un filtro de métricas sobre /demo/legacy-batch y una alarma cuando aparece "ERROR".
# La alarma sirve para disparar la investigación (webhook, EventBridge o a mano).
set -euo pipefail
REGION="${AWS_REGION:-us-east-1}"
LG=/demo/legacy-batch

aws logs create-log-group --log-group-name "$LG" --region "$REGION" 2>/dev/null || true
aws logs put-retention-policy --log-group-name "$LG" --retention-in-days 7 --region "$REGION"

aws logs put-metric-filter --region "$REGION" --log-group-name "$LG" \
  --filter-name batch-errors --filter-pattern "ERROR" \
  --metric-transformations metricName=BatchErrors,metricNamespace=DemoLegacyBatch,metricValue=1,defaultValue=0

aws cloudwatch put-metric-alarm --region "$REGION" \
  --alarm-name legacy-batch-job-failed \
  --alarm-description "El job batch Java legado registró ERROR" \
  --namespace DemoLegacyBatch --metric-name BatchErrors \
  --statistic Sum --period 300 --evaluation-periods 1 --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold --treat-missing-data notBreaching

echo "Alarma legacy-batch-job-failed creada."
