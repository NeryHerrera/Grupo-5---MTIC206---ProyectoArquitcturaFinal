# CloudFormation Stack - Sistema de Control de Inventario con Visión Artificial

Este directorio contiene la plantilla de **AWS CloudFormation** (Infrastructure as Code) para desplegar la arquitectura Serverless del proyecto **Grupo 5 - MTIC206**.

## 📋 Descripción del Stack

El archivo `inventario-sme-stack.yaml` define todos los recursos necesarios para el sistema automatizado de control de inventario:

### Recursos incluidos (24 total):

- **Amazon S3**: Bucket para alojamiento del frontend estático
- **Amazon DynamoDB**: Tabla `TablaInventarioPyME` con modelo On-Demand + GSI
- **AWS Lambda**: 2 funciones (Node.js 24.x)
  - `ProcesarIngresoIAFunction`: Analiza imágenes con Rekognition y actualiza inventario
  - `GestionarSalidasAlertasFunction`: Gestiona salidas y dispara alertas SNS
- **Amazon Rekognition**: Servicio de visión artificial (DetectLabels)
- **Amazon API Gateway**: REST API con rutas `/ingreso` y `/salida`
- **Amazon SNS**: Topic para alertas de stock bajo
- **AWS IAM**: Rol con privilegios mínimos `LambdaInventoryExecutionRole`
- **AWS CloudWatch**: Log Groups con retención de 14 días
- **AWS ApiGateway**: API Key + Usage Plan para seguridad

## 🔧 Prerequisitos

Antes de desplegar el stack, asegúrate de tener:

1. **AWS CLI** configurado con credenciales válidas:
   ```bash
   aws configure
   ```

2. **Permisos suficientes** en tu cuenta AWS para crear:
   - S3, DynamoDB, Lambda, API Gateway, SNS, IAM, CloudWatch
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

### Opción 1: Usar AWS CLI (recomendado)

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

### Opción 2: AWS CloudFormation Console

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
DynamoDBTableName:        TablaInventarioPyME
SNSTopicArn:              arn:aws:sns:us-east-1:XXXX:Alertas_StockBajo_Topic
ApiKeyId:                 (valor mostrado en outputs)
LambdaExecutionRoleArn:   arn:aws:iam::XXXX:role/LambdaInventoryExecutionRole
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
| CloudWatch | 5 GB logs/mes | ~500 MB/mes | ✅ Cubierto |

**⚠️ Nota importante:** Tras 12 meses de Free Tier, Rekognition pasará a tarifa de pago ($1 por 1,000 imágenes).

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

### Error: "AccessDenied" al crear el stack
- Verifica que tu usuario AWS tenga permisos para los servicios mencionados.
- Mínimo requiere: `s3:*`, `dynamodb:*`, `lambda:*`, `apigateway:*`, `sns:*`, `iam:*`, `logs:*`, `rekognition:*`

### Error: "The provided role does not have permissions to..."
- Asegúrate de incluir `--capabilities CAPABILITY_NAMED_IAM` en el comando create-stack.

### Lambda invokes fail (5xx errors)
- Verifica en CloudWatch Logs que la función tenga acceso a Rekognition y DynamoDB.
- Revisa el rol IAM `LambdaInventoryExecutionRole` tiene las políticas correctas.

### No recibo emails de SNS
- Confirma tu suscripción al topic en el email de confirmación de AWS.
- Verifica que el parámetro `AlertEmail` sea correcto.

## 📚 Referencias

- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [Amazon Rekognition Detection Labels](https://docs.aws.amazon.com/rekognition/latest/dg/labels.html)
- [Amazon DynamoDB On-Demand Billing](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.ReadWriteCapacityMode.html)
- [AWS Free Tier](https://aws.amazon.com/free/)

---

**Autor**: Grupo 5 - MTIC206  
**Fecha**: 2026  
**Versión del Template**: 1.0
