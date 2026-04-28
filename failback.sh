#!/bin/bash

echo "🔄 Iniciando failback a región primaria (us-east-1)..."

# Verificar que primaria esté saludable
echo "⏳ Verificando salud de región primaria..."
curl -s http://primary-alb-dr-190582983.us-east-1.elb.amazonaws.com/health

# Apagar ASG secundario
echo "⬇️ Reduciendo capacidad de región secundaria..."
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name terraform-20260428042135864600000004 \
  --desired-capacity 0 \
  --region us-west-2

echo "✅ Failback completado. App primaria activa en:"
echo "http://primary-alb-dr-190582983.us-east-1.elb.amazonaws.com"