#!/bin/bash
set -euo pipefail

PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
SECONDARY_REGION="${SECONDARY_REGION:-us-west-2}"
PRIMARY_ASG="${PRIMARY_ASG:-$(terraform output -raw primary_asg_name)}"
SECONDARY_ASG="${SECONDARY_ASG:-$(terraform output -raw secondary_asg_name)}"
PRIMARY_RDS_ID="${PRIMARY_RDS_ID:-$(terraform output -raw primary_rds_identifier)}"
SECONDARY_RDS_ID="${SECONDARY_RDS_ID:-$(terraform output -raw secondary_rds_identifier)}"
PRIMARY_ALB="${PRIMARY_ALB:-$(terraform output -raw primary_alb_dns)}"
APP_DNS="${APP_DNS:-$(terraform output -raw app_dns)}"
PRIMARY_DB_SUBNET_GROUP="${PRIMARY_DB_SUBNET_GROUP:-db-subnet-primary}"
SECONDARY_DB_SUBNET_GROUP="${SECONDARY_DB_SUBNET_GROUP:-db-subnet-secondary}"
PRIMARY_DB_INSTANCE_CLASS="${PRIMARY_DB_INSTANCE_CLASS:-db.t3.micro}"
SECONDARY_DB_INSTANCE_CLASS="${SECONDARY_DB_INSTANCE_CLASS:-db.t3.micro}"

wait_for_rds_ready() {
  local region="$1"
  local identifier="$2"

  echo "Esperando que ${identifier} en ${region} esté completamente lista..."

  while true; do
    STATUS=$(aws rds describe-db-instances \
      --region "$region" \
      --db-instance-identifier "$identifier" \
      --query 'DBInstances[0].DBInstanceStatus' \
      --output text)

    PENDING=$(aws rds describe-db-instances \
      --region "$region" \
      --db-instance-identifier "$identifier" \
      --query 'DBInstances[0].PendingModifiedValues' \
      --output json)

    echo "Estado actual: $STATUS | PendingModifiedValues: $PENDING"

    if [[ "$STATUS" == "available" && "$PENDING" == "{}" ]]; then
      echo "${identifier} está completamente estable."
      break
    fi

    sleep 30
  done
}

delete_db_if_exists() {
  local region="$1"
  local identifier="$2"

  if aws rds describe-db-instances --region "$region" --db-instance-identifier "$identifier" >/dev/null 2>&1; then
    echo "Eliminando DB existente ${identifier} en ${region}..."
    aws rds delete-db-instance \
      --region "$region" \
      --db-instance-identifier "$identifier" \
      --skip-final-snapshot >/dev/null

    echo "Esperando eliminación de ${identifier} en ${region}..."
    aws rds wait db-instance-deleted \
      --region "$region" \
      --db-instance-identifier "$identifier"
  fi
}

resolve_sg_id() {
  local region="$1"
  local group_name="$2"
  local sg_id

  sg_id=$(aws ec2 describe-security-groups \
    --region "$region" \
    --filters "Name=group-name,Values=${group_name}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

  if [[ "$sg_id" == "None" || -z "$sg_id" ]]; then
    echo "No se pudo resolver SG ${group_name} en ${region}." >&2
    return 1
  fi

  echo "$sg_id"
}

echo "Iniciando failback a región primaria (${PRIMARY_REGION})..."

echo "Verificando salud de la región primaria..."
curl -fsS "http://${PRIMARY_ALB}/health" >/dev/null

echo "Esperando que la DB secundaria esté disponible..."
aws rds wait db-instance-available \
  --db-instance-identifier "$SECONDARY_RDS_ID" \
  --region "$SECONDARY_REGION"

SECONDARY_DB_ARN=$(aws rds describe-db-instances \
  --region "$SECONDARY_REGION" \
  --db-instance-identifier "$SECONDARY_RDS_ID" \
  --query 'DBInstances[0].DBInstanceArn' \
  --output text)

if [[ "$SECONDARY_DB_ARN" == "None" || -z "$SECONDARY_DB_ARN" ]]; then
  echo "No se pudo obtener ARN de la DB secundaria ${SECONDARY_RDS_ID}." >&2
  exit 1
fi

PRIMARY_SG_ID=$(resolve_sg_id "$PRIMARY_REGION" "primary-rds-sg") || exit 1
SECONDARY_SG_ID=$(resolve_sg_id "$SECONDARY_REGION" "secondary-rds-sg") || exit 1

echo "Eliminando antigua primaria si existe..."
delete_db_if_exists "$PRIMARY_REGION" "$PRIMARY_RDS_ID"

echo "Creando nueva primaria en ${PRIMARY_REGION} desde réplica secundaria..."
aws rds create-db-instance-read-replica \
  --region "$PRIMARY_REGION" \
  --db-instance-identifier "$PRIMARY_RDS_ID" \
  --source-db-instance-identifier "$SECONDARY_DB_ARN" \
  --db-instance-class "$PRIMARY_DB_INSTANCE_CLASS" \
  --db-subnet-group-name "$PRIMARY_DB_SUBNET_GROUP" \
  --vpc-security-group-ids "$PRIMARY_SG_ID" \
  --publicly-accessible >/dev/null

echo "Esperando sincronización inicial..."
aws rds wait db-instance-available \
  --region "$PRIMARY_REGION" \
  --db-instance-identifier "$PRIMARY_RDS_ID"

echo "Promoviendo nueva primaria..."
aws rds promote-read-replica \
  --region "$PRIMARY_REGION" \
  --db-instance-identifier "$PRIMARY_RDS_ID" >/dev/null

echo "Esperando estabilización completa después de promoción..."
wait_for_rds_ready "$PRIMARY_REGION" "$PRIMARY_RDS_ID"

PRIMARY_DB_ARN=$(aws rds describe-db-instances \
  --region "$PRIMARY_REGION" \
  --db-instance-identifier "$PRIMARY_RDS_ID" \
  --query 'DBInstances[0].DBInstanceArn' \
  --output text)

if [[ "$PRIMARY_DB_ARN" == "None" || -z "$PRIMARY_DB_ARN" ]]; then
  echo "No se pudo obtener ARN de la DB primaria ${PRIMARY_RDS_ID}." >&2
  exit 1
fi

echo "Eliminando réplica vieja en secundaria..."
delete_db_if_exists "$SECONDARY_REGION" "$SECONDARY_RDS_ID"

echo "Recreando réplica secundaria desde la nueva primaria..."
aws rds create-db-instance-read-replica \
  --region "$SECONDARY_REGION" \
  --db-instance-identifier "$SECONDARY_RDS_ID" \
  --source-db-instance-identifier "$PRIMARY_DB_ARN" \
  --db-instance-class "$SECONDARY_DB_INSTANCE_CLASS" \
  --db-subnet-group-name "$SECONDARY_DB_SUBNET_GROUP" \
  --vpc-security-group-ids "$SECONDARY_SG_ID" \
  --publicly-accessible >/dev/null

echo "Esperando que la nueva réplica secundaria esté lista..."
wait_for_rds_ready "$SECONDARY_REGION" "$SECONDARY_RDS_ID"

echo "Escalando región primaria..."
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name "$PRIMARY_ASG" \
  --desired-capacity 2 \
  --region "$PRIMARY_REGION"

echo "Reduciendo región secundaria..."
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name "$SECONDARY_ASG" \
  --desired-capacity 0 \
  --region "$SECONDARY_REGION"

echo "Failback completado correctamente."
echo "DNS aplicación: $APP_DNS"
echo "ALB primario: http://$PRIMARY_ALB"