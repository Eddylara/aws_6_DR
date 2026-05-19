#!/bin/bash
set -euo pipefail

PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
PRIMARY_ASG="${PRIMARY_ASG:-$(terraform output -raw primary_asg_name)}"
PRIMARY_ALARM_NAME="${PRIMARY_ALARM_NAME:-route53-primary-health-check-unhealthy}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-300}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-15}"

SCRIPT_START_TIME=$(date +%s)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Simulando caída de la región primaria sin ejecutar failover manual..."
log "Región primaria: ${PRIMARY_REGION}"
log "ASG primario: ${PRIMARY_ASG}"
log "Alarma que debe activarse: ${PRIMARY_ALARM_NAME}"

log "Obteniendo instancias actuales del ASG primario..."
PRIMARY_INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$PRIMARY_ASG" \
  --region "$PRIMARY_REGION" \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState!=`Terminated`].InstanceId' \
  --output text)

if [[ -n "$PRIMARY_INSTANCES" && "$PRIMARY_INSTANCES" != "None" ]]; then
  log "Instancias detectadas: $PRIMARY_INSTANCES"
fi

log "Reduciendo el ASG primario a cero para simular la caída..."
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$PRIMARY_ASG" \
  --min-size 0 \
  --desired-capacity 0 \
  --region "$PRIMARY_REGION" >/dev/null

log "ASG primario actualizado a min=0 y desired=0."

log "Esperando a que CloudWatch cambie la alarma a ALARM..."
while true; do
  elapsed=$(( $(date +%s) - SCRIPT_START_TIME ))
  state=$(aws cloudwatch describe-alarms \
    --alarm-names "$PRIMARY_ALARM_NAME" \
    --region "$PRIMARY_REGION" \
    --query 'MetricAlarms[0].StateValue' \
    --output text 2>/dev/null || echo "UNKNOWN")

  log "Estado actual de la alarma ${PRIMARY_ALARM_NAME}: ${state}"

  if [[ "$state" == "ALARM" ]]; then
    log "La alarma se activó correctamente. El failover automático debería dispararse por SNS/Lambda."
    break
  fi

  if (( elapsed >= WAIT_TIMEOUT_SECONDS )); then
    log "Timeout esperando que la alarma entre en ALARM. Revisa el health check, el ALB y los logs de CloudWatch."
    exit 1
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done

log "Verificación rápida adicional:"
log "  aws cloudwatch describe-alarms --alarm-names ${PRIMARY_ALARM_NAME} --region ${PRIMARY_REGION}"
log "  aws logs tail /aws/lambda/dr-failover-automation --follow"
log "  aws sns list-subscriptions-by-topic --topic-arn <SNS_TOPIC_ARN>"
