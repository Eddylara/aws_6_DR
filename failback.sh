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
  local default_group_name="$2"
  local sg_id

  sg_id=$(aws ec2 describe-security-groups \
    --region "$region" \
    --filters "Name=group-name,Values=${default_group_name}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

  if [[ "$sg_id" == "None" || -z "$sg_id" ]]; then
    return 1
  fi

  echo "$sg_id"
}

echo "Iniciando failback a región primaria (${PRIMARY_REGION})..."

echo "Verificando salud de la región primaria..."
curl -fsS "http://${PRIMARY_ALB}/health" >/dev/null

echo "Verificando que la DB actual en secundaria esté disponible..."
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

PRIMARY_SG_ID="${PRIMARY_DB_SECURITY_GROUP_ID:-}"
if [[ -z "$PRIMARY_SG_ID" ]]; then
  PRIMARY_SG_ID=$(resolve_sg_id "$PRIMARY_REGION" "primary-rds-sg") || {
    echo "No se pudo resolver SG primario automáticamente. Define PRIMARY_DB_SECURITY_GROUP_ID." >&2
    exit 1
  }
fi

SECONDARY_SG_ID="${SECONDARY_DB_SECURITY_GROUP_ID:-}"
if [[ -z "$SECONDARY_SG_ID" ]]; then
  SECONDARY_SG_ID=$(resolve_sg_id "$SECONDARY_REGION" "secondary-rds-sg") || {
    echo "No se pudo resolver SG secundario automáticamente. Define SECONDARY_DB_SECURITY_GROUP_ID." >&2
    exit 1
  }
fi

delete_db_if_exists "$PRIMARY_REGION" "$PRIMARY_RDS_ID"

echo "Creando nueva DB primaria en ${PRIMARY_REGION} como réplica de ${SECONDARY_RDS_ID} (${SECONDARY_REGION})..."
aws rds create-db-instance-read-replica \
  --region "$PRIMARY_REGION" \
  --db-instance-identifier "$PRIMARY_RDS_ID" \
  --source-db-instance-identifier "$SECONDARY_DB_ARN" \
  --db-instance-class "$PRIMARY_DB_INSTANCE_CLASS" \
  --db-subnet-group-name "$PRIMARY_DB_SUBNET_GROUP" \
  --vpc-security-group-ids "$PRIMARY_SG_ID" \
  --publicly-accessible >/dev/null

echo "Esperando sincronización inicial de la nueva DB primaria..."
aws rds wait db-instance-available \
  --db-instance-identifier "$PRIMARY_RDS_ID" \
  --region "$PRIMARY_REGION"

echo "Promoviendo DB de ${PRIMARY_REGION} para volverla primaria..."
aws rds promote-read-replica \
  --region "$PRIMARY_REGION" \
  --db-instance-identifier "$PRIMARY_RDS_ID" >/dev/null

echo "Esperando a que la nueva DB primaria quede disponible tras la promoción..."
aws rds wait db-instance-available \
  --db-instance-identifier "$PRIMARY_RDS_ID" \
  --region "$PRIMARY_REGION"

PRIMARY_DB_ARN=$(aws rds describe-db-instances \
  --region "$PRIMARY_REGION" \
  --db-instance-identifier "$PRIMARY_RDS_ID" \
  --query 'DBInstances[0].DBInstanceArn' \
  --output text)

if [[ "$PRIMARY_DB_ARN" == "None" || -z "$PRIMARY_DB_ARN" ]]; then
  echo "No se pudo obtener ARN de la DB primaria ${PRIMARY_RDS_ID}." >&2
  exit 1
fi

delete_db_if_exists "$SECONDARY_REGION" "$SECONDARY_RDS_ID"

echo "Recreando réplica en ${SECONDARY_REGION} desde la nueva primaria..."
aws rds create-db-instance-read-replica \
  --region "$SECONDARY_REGION" \
  --db-instance-identifier "$SECONDARY_RDS_ID" \
  --source-db-instance-identifier "$PRIMARY_DB_ARN" \
  --db-instance-class "$SECONDARY_DB_INSTANCE_CLASS" \
  --db-subnet-group-name "$SECONDARY_DB_SUBNET_GROUP" \
  --vpc-security-group-ids "$SECONDARY_SG_ID" \
  --publicly-accessible >/dev/null

echo "Esperando a que la réplica secundaria esté disponible y sincronizando..."
aws rds wait db-instance-available \
  --db-instance-identifier "$SECONDARY_RDS_ID" \
  --region "$SECONDARY_REGION"

echo "Aumentando capacidad de la región primaria..."
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name "$PRIMARY_ASG" \
  --desired-capacity 2 \
  --region "$PRIMARY_REGION"

echo "Reduciendo capacidad de la región secundaria..."
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name "$SECONDARY_ASG" \
  --desired-capacity 0 \
  --region "$SECONDARY_REGION"

echo "Failback completado con DB primaria nuevamente en ${PRIMARY_REGION}."
echo "DNS de aplicación: $APP_DNS"
echo "ALB primario directo: http://$PRIMARY_ALB"