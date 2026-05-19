#!/bin/bash
set -euo pipefail

PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
PRIMARY_ASG="${PRIMARY_ASG:-$(terraform output -raw primary_asg_name)}"
PRIMARY_ALB="${PRIMARY_ALB:-$(terraform output -raw primary_alb_dns)}"
DESIRED_CAPACITY="${DESIRED_CAPACITY:-2}"
MIN_SIZE="${MIN_SIZE:-2}"
MAX_SIZE="${MAX_SIZE:-4}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-600}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-15}"

START_TIME=$(date +%s)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Reactivando solo la región primaria..."
log "Región primaria: ${PRIMARY_REGION}"
log "ASG primario: ${PRIMARY_ASG}"
log "ALB primario: ${PRIMARY_ALB}"

log "Restaurando capacidad del ASG primario..."
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$PRIMARY_ASG" \
  --min-size "$MIN_SIZE" \
  --desired-capacity "$DESIRED_CAPACITY" \
  --max-size "$MAX_SIZE" \
  --region "$PRIMARY_REGION" >/dev/null

log "ASG primario actualizado: min=${MIN_SIZE}, desired=${DESIRED_CAPACITY}, max=${MAX_SIZE}."

log "Esperando a que las instancias del ASG primario estén saludables..."
while true; do
  elapsed=$(( $(date +%s) - START_TIME ))

  health_table=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$PRIMARY_ASG" \
    --region "$PRIMARY_REGION" \
    --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
    --output table)

  echo "$health_table"

  healthy_count=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$PRIMARY_ASG" \
    --region "$PRIMARY_REGION" \
    --query 'length(AutoScalingGroups[0].Instances[?HealthStatus==`Healthy` && LifecycleState==`InService`])' \
    --output text)

  if [[ "$healthy_count" != "0" && "$healthy_count" != "None" ]]; then
    log "Instancias saludables detectadas en el ASG primario: ${healthy_count}"
    break
  fi

  if (( elapsed >= WAIT_TIMEOUT_SECONDS )); then
    log "Timeout esperando instancias saludables en la región primaria." >&2
    exit 1
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done

log "Verificando endpoint de salud del ALB primario..."
while true; do
  elapsed=$(( $(date +%s) - START_TIME ))

  if curl -fsS "http://${PRIMARY_ALB}/health" >/dev/null; then
    log "ALB primario respondió correctamente en /health."
    break
  fi

  if (( elapsed >= WAIT_TIMEOUT_SECONDS )); then
    log "Timeout esperando respuesta saludable del ALB primario." >&2
    exit 1
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done

log "Región primaria reactivada. Ahora puedes ejecutar failback.sh cuando quieras mover el tráfico y la base de datos."
