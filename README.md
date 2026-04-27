# DR (Disaster Recovery) - Multi-Region CRUD App

Infraestructura Terraform multi-región para **Disaster Recovery** con app CRUD de personas (Flask + Nginx + MySQL).

## 🏗️ Arquitectura

- **Región primaria** (`us-east-1`): VPC, ALB, ASG (2 instancias), RDS Multi-AZ, S3 bucket origen, DynamoDB.
- **Región secundaria** (`us-west-2`): VPC espejo, ALB, ASG standby (desired=0), RDS read replica, S3 replica CRR, DynamoDB Global Table.

### Stack de la app
- **Frontend**: HTML/CSS/JavaScript (CRUD interactivo).
- **Backend**: Flask (Python).
- **Servidor web**: Nginx (proxy reverso a Flask/Gunicorn).
- **Base de datos**: MySQL (RDS Multi-AZ primaria + read replica secundaria).
- **Archivos**: S3 con replicación entre regiones (CRR).
- **NoSQL**: DynamoDB con Global Tables.

---

## � Prerequisites

### Software requerido
- **Terraform** >= 1.4.0 ([descarga](https://www.terraform.io/downloads))
- **AWS CLI** >= 2.0 ([descarga](https://aws.amazon.com/cli/))
- **Git** ([descarga](https://git-scm.com/))
- **curl** (para pruebas)

Verifica instalación:
```bash
terraform -v
aws --version
git --version
```

### Credenciales AWS
Necesitas:
1. **AWS Account** con permisos en `us-east-1` y `us-west-2`.
2. **AWS credentials** configuradas localmente:

```bash
aws configure
# O establecer variables de entorno:
export AWS_ACCESS_KEY_ID="tu-key"
export AWS_SECRET_ACCESS_KEY="tu-secret"
export AWS_DEFAULT_REGION="us-east-1"
```

### Permisos mínimos IAM
Tu usuario/role debe tener permisos sobre:
- EC2 (VPC, Security Groups, Instances, Auto Scaling)
- RDS (Databases, Subnet Groups)
- ALB/Target Groups
- S3
- DynamoDB
- IAM (roles/policies para S3 CRR)

**Recomendación**: Usa `AdministratorAccess` en desarrollo; limita en producción.

### Límites de AWS
- **VPC por región**: default 5 (este proyecto usa 2).
- **RDS instances**: default 20 (este proyecto usa 2).
- **S3 buckets**: sin límite, pero nombres globales (único).
- **DynamoDB**: OK con plan gratuito.

---

## 🔧 Variables necesarias

### Obligatorias (DEBES especificar)

| Variable | Tipo | Default | Notas |
|----------|------|---------|-------|
| `db_password` | string | - | Contraseña RDS MySQL. Min 8 caracteres, especiales. |

### Opcionales (tienen default)

| Variable | Tipo | Default | Notas |
|----------|------|---------|-------|
| `primary_region` | string | `us-east-1` | Región primaria. |
| `secondary_region` | string | `us-west-2` | Región secundaria. |
| `vpc_cidr` | string | `10.0.0.0/16` | CIDR de VPC (ambas regiones). |
| `public_subnet_1_cidr` | string | `10.0.1.0/24` | Subnet AZ-1. |
| `public_subnet_2_cidr` | string | `10.0.2.0/24` | Subnet AZ-2. |
| `db_name` | string | `appdb` | Nombre de la BD. |
| `db_username` | string | `admin` | Usuario RDS. |
| `source_bucket_name` | string | `bucket-dr-source-proyecto-12345` | **CAMBIAR**: nombres S3 son globales. |
| `destination_bucket_name` | string | `bucket-dr-destination-proyecto-12345` | **CAMBIAR**: nombres S3 son globales. |
| `dynamodb_table_name` | string | `usuarios` | Tabla DynamoDB. |

### Cómo especificar variables

**Opción A: Archivo `terraform.tfvars`** (recomendado)
```hcl
db_password             = "MiPassword123!"
source_bucket_name      = "bucket-dr-source-miempresa-2026"
destination_bucket_name = "bucket-dr-destination-miempresa-2026"
```

**Opción B: Variables de entorno**
```bash
export TF_VAR_db_password="MiPassword123!"
export TF_VAR_source_bucket_name="bucket-dr-source-miempresa-2026"
export TF_VAR_destination_bucket_name="bucket-dr-destination-miempresa-2026"
```

**Opción C: Línea de comando**
```bash
terraform apply -var="db_password=MiPassword123!"
```

**Opción D: Script interactivo**
```bash
./setup-env.sh  # Pide datos y crea terraform.tfvars
```

---

## �🚀 Quick Start

### 1. Clonar y preparar
```bash
git clone <tu-repo>
cd proyecto_6_ddr5
```

### 2. Configurar variables de Terraform (OBLIGATORIO)

**Elige UNA opción:**

#### A) Script interactivo (más fácil) ⭐
```bash
chmod +x setup-env.sh
./setup-env.sh
# Pide db_password y nombres de buckets S3
# Crea terraform.tfvars automáticamente
```

#### B) Copiar plantilla y editar
```bash
cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars con tu editor
# Solo cambiar: db_password, source_bucket_name, destination_bucket_name
```

#### C) Variables de entorno
```bash
# OBLIGATORIO
export TF_VAR_db_password="TuPassword123!"

# RECOMENDADO (buckets globales - debe ser único)
export TF_VAR_source_bucket_name="bucket-dr-source-TUEMPRESA-$(date +%s)"
export TF_VAR_destination_bucket_name="bucket-dr-destination-TUEMPRESA-$(date +%s)"
```

**⚠️ IMPORTANTE:**
- `terraform.tfvars` NO se sube a Git (credenciales).
- El archivo se ignora automáticamente (`.gitignore`).
- Usa `terraform.tfvars.example` como plantilla.

### 3. Validar configuración
```bash
terraform validate
# Debe decir: "Success! The configuration is valid."

terraform plan -out=tfplan
# Revisa qué recursos se crearán
```

### 4. Desplegar
```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 4. Desplegar
```bash
# Crear tfplan
terraform plan -out=tfplan

# Revisar recursos a crear (IMPORTANTE)
terraform show tfplan | less

# Aplicar cambios (LENTO: 15-20 min)
terraform apply tfplan

# Al terminar, obtener outputs
terraform output
```

### 5. Obtener URLs para pruebas
### 5. Obtener URLs para pruebas
```bash
terraform output primary_alb_dns      # ALB de primaria
terraform output secondary_alb_dns    # ALB de secundaria
terraform output rds_primary_endpoint # BD primaria
terraform output s3_source_bucket     # S3 origen
```

### ⏱️ Tiempo estimado
- `terraform init`: 2-3 min (primera vez).
- `terraform plan`: 1-2 min.
- `terraform apply`: **15-20 min** (RDS tarda mucho).
  - VPC/ALB/EC2: 3 min.
  - RDS Multi-AZ: 10-15 min.
  - EC2 user-data (Flask): 3-5 min.

### 💰 Costos estimados (AWS Free Tier insuficiente)
| Recurso | Cantidad | Costo/mes (aprox) |
|---------|----------|-------------------|
| EC2 (t3.micro) | 2-4 | $10-20 |
| RDS MySQL (t3.micro) | 2 (primaria + replica) | $30-50 |
| ALB | 2 | $16-32 |
| Data Transfer (CRR) | variable | $2-10 |
| S3 | mínimo | $1-5 |
| DynamoDB | PAY_PER_REQUEST | $0-2 |
| **TOTAL** | | **$60-120/mes** |

Para **detener costos**: `terraform destroy` (elimina todo).

---

## 🧪 Pruebas

### Primaria (us-east-1)
```bash
ALB=$(terraform output -raw primary_alb_dns)
curl http://$ALB/health
curl http://$ALB/  # CRUD web
```

### Crear persona
```bash
curl -X POST http://$ALB/api/personas \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Juan","edad":30}'
```

### Listar personas
```bash
curl http://$ALB/api/personas
```

### Validar réplica RDS (secundaria)
```bash
# En AWS Console:
# RDS > Databases > db-dr-secondary-replica
# Estado debe ser "Available"
# Lag debe ser bajo (< 100ms)
```

### Validar S3 CRR
```bash
# Subir archivo al bucket origen
aws s3 cp archivo.txt s3://bucket-dr-source-*

# Verificar en bucket destino
aws s3 ls s3://bucket-dr-destination-* --recursive
```

---

## 🔄 Failover a Secundaria

### Escalable (temporal):
```bash
# Activar ASG secundario
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name secondary-asg-dr \
  --desired-capacity 2 \
  --region us-west-2

# Esperar 3-5 min a que instancias estén healthy
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names secondary-asg-dr \
  --region us-west-2 \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus]'

# Probar ALB secundario
ALB_SEC=$(terraform output -raw secondary_alb_dns)
curl http://$ALB_SEC/  
```

### Promoción de DB (no reversible - usar en emergencia):
```bash
# Promover read replica a instance writable
aws rds promote-read-replica \
  --db-instance-identifier db-dr-secondary-replica \
  --region us-west-2

# ADVERTENCIA: Después de esto, primaria y secundaria no estarán sincronizadas
# Necesitarás runbook de recuperación manual
```

---

## 📁 Estructura

```
.
├── main.tf                 # Orquestación multi-región
├── provider.tf             # Providers AWS (primary/secondary)
├── variables.tf            # Variables (región, CIDR, credenciales)
├── outputs.tf              # Outputs (ALB, RDS endpoints)
├── terraform.tfvars        # ❌ NO SUBIR (credenciales)
├── terraform.tfvars.example # ✅ Plantilla para compañeros
├── .gitignore              # Archivos ignorados
├── setup-env.sh            # Script de setup interactivo
├── SETUP.md                # Esta guía
├── modules/
│   ├── vpc/                # VPC + subnets + IGW
│   ├── alb/                # ALB + Target Group
│   ├── ec2_asg/            # Launch Template + ASG
│   ├── rds/                # RDS primaria + read replica
│   ├── s3/                 # S3 buckets + CRR
│   └── dynamodb/           # DynamoDB Global Table
└── app/
    ├── app.py              # Flask app (CRUD)
    ├── requirements.txt    # Deps (Flask, PyMySQL, Gunicorn)
    └── templates/
        └── index.html      # Frontend CRUD
```

---

## 🔐 Seguridad

- ✅ Credenciales en `terraform.tfvars` (excluido de Git).
- ✅ Variables de ambiente para CI/CD.
- ✅ Security Groups restrictivos por capa (ALB, EC2, RDS).
- ✅ Nginx proxy en EC2 (no expone Flask directamente).
- ✅ RDS no públicamente accesible.

**NO dataría credenciales en plaintext en repos públicos.** Usa AWS Secrets Manager o HashiCorp Vault en producción.

---

## 📋 Checklist de validación

- [ ] Terraform apply exitoso sin errores.
- [ ] Primaria: ALB accesible, 2 EC2 saludables.
- [ ] Secundaria: RDS read replica lag < 100ms.
- [ ] S3: Archivo en origen aparece en destino (< 15 min).
- [ ] DynamoDB: Tabla global visible en ambas regiones.
- [ ] CRUD: POST/GET/PUT/DELETE funciona.

---

## 🛠️ Troubleshooting

### EC2 no levanta
```bash
# Revisar user data
aws ec2 describe-instances --region us-east-1 \
  --query 'Reservations[0].Instances[0].{ID:InstanceId,State:State.Name,LaunchTime:LaunchTime}'

# Logs en instancia
# /var/log/cloud-init-output.log
```

### RDS replica lag alto
```bash
aws rds describe-db-instances --db-instance-identifier db-dr-secondary-replica \
  --region us-west-2 \
  --query 'DBInstances[0].{Endpoint:Endpoint.Address,Status:DBInstanceStatus,ReplicationLag:LatestRestorableTime}'
```

### S3 CRR lento
```bash
# Ver regla de replicación
aws s3api get-bucket-replication --bucket bucket-dr-source-* \
  --region us-east-1
```

---

## 📝 To-Do
- [ ] Agregar Route53 para DNS multi-región.
- [ ] Agregar script automático de failover.
- [ ] Agregar CloudWatch alarms.
- [ ] Agregar Lambda para orquestación.

---

## 📧 Soporte
Contacta al equipo DevOps si hay issues.

---

**Última actualización**: 27 Abril 2026
