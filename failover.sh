#!/bin/bash

echo "🚨 Iniciando failover a región secundaria (us-west-2)..."

# Activar ASG secundario
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name terraform-20260428042135864600000004 \
  --desired-capacity 2 \
  --region us-west-2

echo "⏳ Esperando que las instancias secundarias estén saludables..."
sleep 60

# Verificar estado
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names terraform-20260428042135864600000004 \
  --region us-west-2 \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus]' \
  --output table

echo "✅ Failover completado. App secundaria disponible en:"
echo "http://secondary-alb-dr-1226314603.us-west-2.elb.amazonaws.com"