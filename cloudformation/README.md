# CloudFormation Stack - Sistema de Control de Inventario con Visión Artificial

Este directorio contiene la plantilla de **AWS CloudFormation** (Infrastructure as Code) para desplegar la arquitectura Serverless del proyecto **Grupo 5 - MTIC206**.

## 📋 Descripción del Stack

El archivo `inventario-sme-stack.yaml` define todos los recursos necesarios para el sistema automatizado de control de inventario:

### Recursos incluidos:

- **Amazon S3**: Bucket frontend + bucket staging CSV + bucket assets Glue (scripts/temp)
- **Amazon DynamoDB**: Tabla `TablaInventarioPyME` con modelo On-Demand + GSI
- **AWS Lambda**: 3 funciones (Node.js 24.x) — ingreso IA, salidas/alertas, listar inventario
- **AWS Glue**: Data Catalog, Crawler, Job Spark ETL (`CargaInventarioGlueJob`)
- **Amazon EventBridge**: Regla que dispara Glue al subir `.csv` al bucket staging
- **Amazon Rekognition**: Servicio de visión artificial (DetectLabels)
- **Amazon API Gateway**: REST API con rutas `/ingreso`, `/salida` e `/inventario`
- **Amazon SNS**: Topic para alertas de stock bajo
- **AWS IAM**: Roles (`LambdaInventoryExecutionRole`, `GlueEtlExecutionRole`, `GlueCrawlerRole`, `EventBridgeGlueStartRole`)
- **AWS CloudWatch**: Log Groups Lambda + logs Glue (`/aws-glue/jobs/*`)
- **AWS ApiGateway**: API Key + Usage Plan para seguridad

## 🔧 Prerequisitos

Antes de desplegar el stack, asegúrate de tener:

1. **AWS CLI** configurado con credenciales válidas:
   ```bash
   aws configure
   ```

2. **Permisos suficientes** en tu cuenta AWS para crear:
   - S3, DynamoDB, Lambda, API Gateway, SNS, IAM, CloudWatch, Glue, EventBridge
   - Típicamente requiere rol `AdministratorAccess` o equivalente

3. **Región AWS**: Se recomienda usar regiones que soporten todos los servicios (ej. `us-east-1`, `eu-west-1`)

## 📝 Parámetros

El stack acepta los siguientes parámetros al desplegar:

| Parámetro | Tipo | Predeterminado | Descripción |
|-----------|------|----------------|-------------|
| `AlertEmail` | String | *(requerido)* | Correo del administrador que recibirá las alertas SNS |
| `ProjectName` | String | `inventario-sme` | Prefijo para nombrar recursos |
| `StockBajoUmbral` | Number | `5` | Umbral de unidades para disparar alerta de stock bajo |

## 🚀 Despliegue

### Opción 1: GitHub Actions con OIDC (recomendado)

Despliegue automático al hacer push a `main` (cambios en `cloudformation/inventario-sme-stack.yaml`) o manualmente desde la pestaña **Actions**.

**Workflows:**
- `.github/workflows/deploy-infrastructure.yml` — crea o actualiza el stack
- `.github/workflows/validate-infrastructure.yml` — valida la plantilla en pull requests

#### Checklist A — Configurar AWS (una sola vez)

1. Anota tu **Account ID** (consola AWS → clic en tu usuario arriba a la derecha).

2. **IAM → Identity providers → Add provider**
   - Tipo: OpenID Connect
   - URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`

3. **IAM → Roles → Create role**
   - Trusted entity: **Web identity**
   - Provider: `token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`
   - Edita la trust policy con [`iam/github-oidc-trust-policy.json`](iam/github-oidc-trust-policy.json):
     - Reemplaza `ACCOUNT_ID` por tu ID de cuenta
     - Reemplaza `GITHUB_ORG/GITHUB_REPO` por tu repo (ej. `mi-usuario/Grupo-5---MTIC206---ProyectoArquitcturaFinal`)
   - Nombre sugerido: `GitHubActions-InventarioSme-DeployRole`
   - Adjunta la política de [`iam/github-actions-deploy-policy.json`](iam/github-actions-deploy-policy.json) como **inline policy**
   - Si el primer deploy falla por permisos, adjunta temporalmente `AdministratorAccess` para desbloquear el piloto
   - Copia el **ARN del rol**

4. Fija la región de trabajo (ej. `us-east-1`).

#### Checklist B — Configurar GitHub

En el repo: **Settings → Secrets and variables → Actions**

**Variables:**

| Variable | Ejemplo |
|----------|---------|
| `AWS_ROLE_ARN` | `arn:aws:iam::123456789012:role/GitHubActions-InventarioSme-DeployRole` |
| `AWS_REGION` | `us-east-1` |
| `PROJECT_NAME` | `inventario-sme` (opcional) |
| `STOCK_BAJO_UMBRAL` | `5` (opcional) |

**Secrets:**

| Secret | Descripción |
|--------|-------------|
| `ALERT_EMAIL` | Correo del gerente para alertas SNS |

Verifica que **Actions** esté habilitado en Settings → Actions → General.

#### Checklist C — Primer despliegue

1. Push a la rama `main` con los workflows incluidos.
2. GitHub → **Actions** → **Deploy Infrastructure** → **Run workflow** (si no se disparó solo).
3. Espera `CREATE_COMPLETE` o `UPDATE_COMPLETE` en los logs.
4. Revisa el **Job summary** con los outputs del stack.
5. En AWS CloudFormation, confirma el stack `inventario-sme-stack`.

#### Checklist D — Post-deploy manual

| Paso | Acción |
|------|--------|
| 1 | Confirmar suscripción SNS en el correo de AWS |
| 2 | Obtener valor de API Key (ver sección [API Key](#-api-key)) |
| 3 | Subir `Frontend/prototipo/index.html` al bucket S3 del frontend |
| 4 | Configurar URL de API + API Key en la interfaz web |
| 5 | Subir script Glue a `GlueAssetsBucket` (automático con `deploy.sh`) |
| 6 | Subir CSV al bucket staging → verificar Glue Job `CargaInventarioGlueJob` |

**Subir frontend (PowerShell):**

```powershell
aws s3 cp Frontend/prototipo/index.html s3://inventario-sme-frontend-bucket-<ACCOUNT_ID>/index.html --region us-east-1
```

#### Flujo continuo

```
Cambio en inventario-sme-stack.yaml
  → PR a main → Validate Infrastructure
  → Merge → Deploy Infrastructure (automático)
```

Para cambiar email o umbral: edita Variables/Secrets en GitHub y ejecuta **Deploy Infrastructure** manualmente.

---

### Opción 2: Script deploy.sh (CLI + script Glue)

Desde el directorio `cloudformation/`:

```bash
bash deploy.sh
```

El script crea o actualiza el stack y sube automáticamente `glue/scripts/carga_inventario_etl.py` al bucket `GlueAssetsBucket`.

### Opción 3: AWS CLI manual

```bash
aws cloudformation create-stack \
  --stack-name inventario-sme-stack \
  --template-body file://inventario-sme-stack.yaml \
  --parameters ParameterKey=AlertEmail,ParameterValue=gerente@ejemplo.com \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

**Espera a que el stack se cree completamente:**
```bash
aws cloudformation describe-stacks \
  --stack-name inventario-sme-stack \
  --query 'Stacks[0].StackStatus' \
  --region us-east-1
```

El estado debe cambiar a `CREATE_COMPLETE`.

### Actualizar un stack existente

Si el stack ya está desplegado y agregaste recursos ETL u otros cambios al template:

```bash
aws cloudformation update-stack \
  --stack-name inventario-sme-stack \
  --template-body file://inventario-sme-stack.yaml \
  --parameters ParameterKey=AlertEmail,ParameterValue=gerente@ejemplo.com \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

Espera hasta que el estado sea `UPDATE_COMPLETE`.

Luego sube el script Glue (requerido antes del primer run):

```bash
aws s3 cp ../glue/scripts/carga_inventario_etl.py \
  s3://inventario-sme-glue-assets-ACCOUNT_ID/scripts/carga_inventario_etl.py \
  --region us-east-1
```

## ETL: Carga inicial con AWS Glue

Pobla DynamoDB subiendo un CSV al bucket staging. **AWS Glue** (job Spark) ejecuta Extract → Transform → Load hacia `TablaInventarioPyME`.

**Flujo:** CSV en `inventario-sme-staging-csv-{AccountId}` → EventBridge (`InventarioCsvUploadRule`) → Glue Job `CargaInventarioGlueJob` → DynamoDB (overwrite por `productoId`).

**Componentes Glue en el stack:**

| Recurso | Función |
|---------|---------|
| `inventario_sme_staging` | Base de datos Data Catalog |
| `inventario_csv` | Tabla externa CSV |
| `InventarioCsvCrawler` | Descubre/actualiza esquema (ejecución manual opcional) |
| `CargaInventarioGlueJob` | Job Spark ETL (PySpark + boto3) |

**Script en repo:** [`glue/scripts/carga_inventario_etl.py`](../glue/scripts/carga_inventario_etl.py)

**Archivo de ejemplo en el repositorio:** [`data/inventario-inicial-ejemplo.csv`](../data/inventario-inicial-ejemplo.csv)

**Formato CSV:**

```csv
productoId,nombre,categoria,cantidad
banana,Platano,Refrigerador,24
```

Categorías válidas: `Refrigerador`, `Congelador`, `Bodega Seca`, `Sin Clasificar`.

**Guía paso a paso en consola AWS:** [`docs-aux/guia-carga-csv-staging.md`](../docs-aux/guia-carga-csv-staging.md)

**Carga vía CLI (alternativa):**

```bash
aws s3 cp ../data/inventario-inicial-ejemplo.csv s3://inventario-sme-staging-csv-ACCOUNT_ID/inventario-inicial-ejemplo.csv --region us-east-1
```

Reemplaza `ACCOUNT_ID` por tu ID de cuenta AWS (visible en el output `StagingCsvBucketName`).

### Opción 4: AWS CloudFormation Console

1. Abre la [AWS CloudFormation Console](https://console.aws.amazon.com/cloudformation)
2. Clic en **Create Stack** → **With new resources**
3. Selecciona **Upload a template file** y carga `inventario-sme-stack.yaml`
4. Ingresa el stack name: `inventario-sme-stack`
5. En **Parameters**, proporciona:
   - **AlertEmail**: tu-correo@ejemplo.com
6. Clic en **Next** → **Next** (skip review)
7. En **Review**, marca el checkbox: *"I acknowledge that AWS CloudFormation might create IAM resources"*
8. Clic en **Create Stack**

## 📊 Outputs (Salidas)

Tras desplegar exitosamente, el stack genera los siguientes outputs:

```
FrontendBucketWebsiteURL: https://inventario-sme-frontend-bucket-XXXX.s3-website-us-east-1.amazonaws.com
ApiInvokeURL:             https://XXXXXXXXXX.execute-api.us-east-1.amazonaws.com/prod
IngresoEndpoint:          https://XXXXXXXXXX.execute-api.us-east-1.amazonaws.com/prod/ingreso
SalidaEndpoint:           https://XXXXXXXXXX.execute-api.us-east-1.amazonaws.com/prod/salida
InventarioEndpoint:       https://XXXXXXXXXX.execute-api.us-east-1.amazonaws.com/prod/inventario
StagingCsvBucketName:     inventario-sme-staging-csv-XXXXXXXXXXXX
GlueAssetsBucketName:     inventario-sme-glue-assets-XXXXXXXXXXXX
CargaInventarioGlueJobName: CargaInventarioGlueJob
InventarioStagingDatabaseName: inventario_sme_staging
InventarioCsvCrawlerName: InventarioCsvCrawler
DynamoDBTableName:        TablaInventarioPyME
SNSTopicArn:              arn:aws:sns:us-east-1:XXXX:Alertas_StockBajo_Topic
ApiKeyId:                 (valor mostrado en outputs)
LambdaExecutionRoleArn:   arn:aws:iam::XXXX:role/LambdaInventoryExecutionRole
GlueEtlExecutionRoleArn:  arn:aws:iam::XXXX:role/GlueEtlExecutionRole
```

**Para obtener los outputs via CLI:**
```bash
aws cloudformation describe-stacks \
  --stack-name inventario-sme-stack \
  --query 'Stacks[0].Outputs' \
  --region us-east-1
```

## 🔐 API Key

La API requiere un **API Key** para autenticar peticiones (capa de seguridad adicional).

**Para obtener el valor de la API Key:**
```bash
aws apigateway get-api-key \
  --api-key <ApiKeyId> \
  --include-value \
  --region us-east-1
```

**Para usar la API con la key:**
```bash
curl -X POST https://XXXXXXXXXX.execute-api.us-east-1.amazonaws.com/prod/ingreso \
  -H "X-Api-Key: tu-api-key-aqui" \
  -H "Content-Type: application/json" \
  -d '{
    "imagenBase64": "BASE64_ENCODED_IMAGE",
    "cantidad": 1
  }'
```

## 💰 Costos (AWS Free Tier)

El stack está diseñado para permanecer dentro de los límites del **AWS Free Tier** durante los primeros 12 meses:

| Servicio | Límite Free Tier | Uso Estimado | Estado |
|----------|------------------|--------------|--------|
| S3 | 5 GB + 20K GETS | < 500 MB + 5K GETS/mes | ✅ Cubierto |
| Lambda | 1M requests + 400K GB-s | ~15K requests + 15K GB-s/mes | ✅ Cubierto |
| DynamoDB | 25 GB + 25 RCU/WCU | < 100 MB + < 5 RCU/WCU | ✅ Cubierto |
| API Gateway | 1M calls | ~15K calls/mes | ✅ Cubierto |
| Rekognition | 5K images (12 meses) | ~3K images/mes | ✅ Cubierto |
| SNS | 1K emails/mes | ~200 emails/mes | ✅ Cubierto |
| CloudWatch | 5 GB logs/mes | ~500 MB/mes | Cubierto |
| AWS Glue | 1 DPU-hora/mes (12 meses) | ~0.03 DPU-h por carga CSV | Cubierto en piloto |

**Nota Glue:** cada ejecución del job Spark (2 workers G.1X, ~1–2 min) consume fracciones de DPU-hora; costo marginal bajo en POC.

## 🗑️ Eliminar el Stack

Para limpiar todos los recursos y evitar costos:

```bash
aws cloudformation delete-stack \
  --stack-name inventario-sme-stack \
  --region us-east-1
```

**Verificar eliminación:**
```bash
aws cloudformation describe-stacks \
  --stack-name inventario-sme-stack \
  --region us-east-1
```

El estado debe cambiar a `DELETE_COMPLETE` o mostrar error de stack no encontrado.

## 🐛 Troubleshooting

### Error en GitHub Actions: "Not authorized to perform sts:AssumeRoleWithWebIdentity"
- Verifica que el OIDC provider exista en IAM.
- Revisa la trust policy: el `sub` debe ser exactamente `repo:ORG/REPO:ref:refs/heads/main`.
- Confirma que `AWS_ROLE_ARN` en GitHub Variables sea el ARN correcto.

### Error en GitHub Actions: "ALERT_EMAIL no esta configurado"
- Crea el secret `ALERT_EMAIL` en Settings → Secrets and variables → Actions.

### Error: "AccessDenied" al crear el stack
- Verifica que tu usuario AWS tenga permisos para los servicios mencionados.
- Mínimo requiere: `s3:*`, `dynamodb:*`, `lambda:*`, `apigateway:*`, `sns:*`, `iam:*`, `logs:*`, `rekognition:*`, `glue:*`, `events:*`

### Error: "The provided role does not have permissions to..."
- Asegúrate de incluir `--capabilities CAPABILITY_NAMED_IAM` en el comando create-stack.

### Lambda invokes fail (5xx errors)
- Verifica en CloudWatch Logs que la función tenga acceso a Rekognition y DynamoDB.
- Revisa el rol IAM `LambdaInventoryExecutionRole` tiene las políticas correctas.

### No recibo emails de SNS
- Confirma tu suscripción al topic en el email de confirmación de AWS.
- Verifica que el parámetro `AlertEmail` sea correcto.

### El ETL Glue no procesa el CSV
- Verifica que el archivo termine en `.csv` y esté en `StagingCsvBucketName`.
- Confirma que el script exista en `s3://GlueAssetsBucketName/scripts/carga_inventario_etl.py`.
- Revisa **AWS Glue → ETL jobs → CargaInventarioGlueJob → Runs** (estado y logs).
- CloudWatch: `/aws-glue/jobs/output` y `/aws-glue/jobs/error`.
- Verifica la regla EventBridge `InventarioCsvUploadRule` en estado **Enabled**.

## 📚 Referencias

- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [AWS Glue Developer Guide](https://docs.aws.amazon.com/glue/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [Amazon Rekognition Detection Labels](https://docs.aws.amazon.com/rekognition/latest/dg/labels.html)
- [Amazon DynamoDB On-Demand Billing](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.ReadWriteCapacityMode.html)
- [AWS Free Tier](https://aws.amazon.com/free/)

---

**Autor**: Grupo 5 - MTIC206  
**Fecha**: 2026  
**Versión del Template**: 1.2
