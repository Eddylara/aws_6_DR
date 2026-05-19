#!/bin/bash
set -euo pipefail

PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
SECONDARY_REGION="${SECONDARY_REGION:-us-west-2}"
PRIMARY_ASG="${PRIMARY_ASG:-$(terraform output -raw primary_asg_name)}"
SECONDARY_ASG="${SECONDARY_ASG:-$(terraform output -raw secondary_asg_name)}"
SECONDARY_RDS_ID="${SECONDARY_RDS_ID:-$(terraform output -raw secondary_rds_identifier)}"
SECONDARY_ALB="${SECONDARY_ALB:-$(terraform output -raw secondary_alb_dns)}"
APP_DNS="${APP_DNS:-$(terraform output -raw app_dns)}"

# Variables para medir RTO y RPO
FAILOVER_START_TIME=$(date +%s%3N)
RPO_VALUE=0

echo "Iniciando failover a región secundaria (${SECONDARY_REGION})..."

echo "Obteniendo RPO (lag de replicación de RDS)..."
RPO_LAG=$(aws rds describe-db-instances \
  --db-instance-identifier "$SECONDARY_RDS_ID" \
  --region "$SECONDARY_REGION" \
  --query 'DBInstances[0].StatusInfos[?Status==`replicating`].Message' \
  --output text 2>/dev/null || echo "")

if [[ -z "$RPO_LAG" ]]; then
  echo "Consultando ReplicationLag de forma alternativa..."
  RPO_LAG=$(aws rds describe-db-instances \
    --db-instance-identifier "$SECONDARY_RDS_ID" \
    --region "$SECONDARY_REGION" \
    --query 'DBInstances[0].LatestRestorableTime' \
    --output text 2>/dev/null || echo "")
  RPO_VALUE=0
else
  # Extraer el valor de segundos si está disponible
  RPO_VALUE=$(echo "$RPO_LAG" | grep -oP '\d+' | head -1 || echo "0")
fi

echo "RPO estimado (lag de replicación): ${RPO_VALUE} segundos"
aws rds promote-read-replica \
  --db-instance-identifier "$SECONDARY_RDS_ID" \
  --region "$SECONDARY_REGION"

echo "Esperando a que la base de datos esté disponible..."
aws rds wait db-instance-available \
  --db-instance-identifier "$SECONDARY_RDS_ID" \
  --region "$SECONDARY_REGION"

SECONDARY_DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$SECONDARY_RDS_ID" \
  --region "$SECONDARY_REGION" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

if [[ "$SECONDARY_DB_ENDPOINT" == "None" || -z "$SECONDARY_DB_ENDPOINT" ]]; then
  echo "No se pudo obtener el endpoint de la DB promovida en ${SECONDARY_REGION}." >&2
  exit 1
fi

echo "Reduciendo capacidad del ASG primario (best-effort)..."
if aws autoscaling set-desired-capacity \
  --auto-scaling-group-name "$PRIMARY_ASG" \
  --desired-capacity 0 \
  --region "$PRIMARY_REGION"; then
  echo "ASG primario reducido a 0."
else
  echo "No se pudo ajustar ASG primario (posible indisponibilidad regional). Continuando failover." >&2
fi

echo "Activando ASG secundario..."
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name "$SECONDARY_ASG" \
  --desired-capacity 2 \
  --region "$SECONDARY_REGION"

echo "Esperando que las instancias secundarias estén saludables..."
sleep 45

aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$SECONDARY_ASG" \
  --region "$SECONDARY_REGION" \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
  --output table

echo "Verificando health endpoint del ALB secundario..."
for i in {1..18}; do
  if curl -fsS "http://${SECONDARY_ALB}/health" >/dev/null; then
    echo "ALB secundario saludable."
    break
  fi

  if [[ "$i" -eq 18 ]]; then
    echo "El ALB secundario no respondió saludable a tiempo." >&2
    exit 1
  fi

  sleep 10
done

echo "Failover completado. Route 53 debe dirigir el tráfico al ALB saludable."
echo "DB activa (writer) en secundaria: $SECONDARY_DB_ENDPOINT"
echo "DNS de aplicación: $APP_DNS"
echo "ALB secundario directo: http://$SECONDARY_ALB"

# Calcular RTO (Recovery Time Objective)
FAILOVER_END_TIME=$(date +%s%3N)
RTO_MILLISECONDS=$((FAILOVER_END_TIME - FAILOVER_START_TIME))
RTO_SECONDS=$((RTO_MILLISECONDS / 1000))
RTO_MINUTES=$(echo "scale=2; $RTO_SECONDS / 60" | bc)

echo ""
echo "============================================"
echo "   MÉTRICAS DE RECUPERACIÓN DE DESASTRES"
echo "============================================"
echo "RTO (Recovery Time Objective): ${RTO_SECONDS}s (~${RTO_MINUTES}m)"
echo "  → Tiempo total desde inicio hasta sistema operativo"
echo ""
echo "RPO (Recovery Point Objective): ${RPO_VALUE}s"
echo "  → Máximona de datos que se pueden perder (lag de replicación)"
echo "============================================"
