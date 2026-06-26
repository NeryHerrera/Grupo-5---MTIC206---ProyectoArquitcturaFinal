#!/bin/bash
# Script de despliegue del stack CloudFormation + script Glue ETL
# Grupo 5 - MTIC206 - Sistema de Control de Inventario

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== CloudFormation Stack Deployment ===${NC}"
echo ""

if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI no esta instalado. Instalalo con: pip install awscli"
    exit 1
fi

STACK_NAME="inventario-sme-stack"
TEMPLATE_FILE="inventario-sme-stack.yaml"
GLUE_SCRIPT="../glue/scripts/carga_inventario_etl.py"
REGION="${AWS_REGION:-us-east-1}"

read -p "Ingresa el correo del administrador (para alertas SNS): " ALERT_EMAIL

if [ -z "$ALERT_EMAIL" ]; then
    echo "Error: Correo es requerido."
    exit 1
fi

if [ ! -f "$GLUE_SCRIPT" ]; then
    echo "Error: No se encontro el script Glue en $GLUE_SCRIPT"
    exit 1
fi

echo ""
echo -e "${YELLOW}Parametros de despliegue:${NC}"
echo "  Stack Name: $STACK_NAME"
echo "  Template: $TEMPLATE_FILE"
echo "  Glue Script: $GLUE_SCRIPT"
echo "  Alert Email: $ALERT_EMAIL"
echo "  Region: $REGION"
echo ""

read -p "Continuar con el despliegue? (y/n): " CONTINUE

if [[ "$CONTINUE" != "y" ]]; then
    echo "Despliegue cancelado."
    exit 0
fi

echo ""
STACK_EXISTS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].StackStatus' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "$STACK_EXISTS" == "NOT_FOUND" ]]; then
    echo -e "${YELLOW}Creando stack nuevo...${NC}"
    aws cloudformation create-stack \
      --stack-name "$STACK_NAME" \
      --template-body file://"$TEMPLATE_FILE" \
      --parameters ParameterKey=AlertEmail,ParameterValue="$ALERT_EMAIL" \
      --capabilities CAPABILITY_NAMED_IAM \
      --region "$REGION" \
      --no-paginate

    echo -e "${YELLOW}Esperando CREATE_COMPLETE (puede tomar 5-8 minutos con Glue)...${NC}"
    aws cloudformation wait stack-create-complete \
      --stack-name "$STACK_NAME" \
      --region "$REGION"
else
    echo -e "${YELLOW}Stack existente ($STACK_EXISTS). Actualizando...${NC}"
    aws cloudformation update-stack \
      --stack-name "$STACK_NAME" \
      --template-body file://"$TEMPLATE_FILE" \
      --parameters ParameterKey=AlertEmail,ParameterValue="$ALERT_EMAIL" \
      --capabilities CAPABILITY_NAMED_IAM \
      --region "$REGION" \
      --no-paginate || {
        STATUS=$?
        if aws cloudformation describe-stacks \
          --stack-name "$STACK_NAME" \
          --region "$REGION" \
          --query 'Stacks[0].StackStatus' \
          --output text 2>/dev/null | grep -q "UPDATE_COMPLETE"; then
            echo "Sin cambios en el template."
        else
            exit $STATUS
        fi
      }

    echo -e "${YELLOW}Esperando UPDATE_COMPLETE...${NC}"
    aws cloudformation wait stack-update-complete \
      --stack-name "$STACK_NAME" \
      --region "$REGION" 2>/dev/null || true
fi

echo -e "${GREEN}Stack desplegado correctamente.${NC}"
echo ""

GLUE_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='GlueAssetsBucketName'].OutputValue" \
  --output text \
  --region "$REGION")

echo -e "${YELLOW}Subiendo script Glue a s3://${GLUE_BUCKET}/scripts/...${NC}"
aws s3 cp "$GLUE_SCRIPT" "s3://${GLUE_BUCKET}/scripts/carga_inventario_etl.py" --region "$REGION"

echo -e "${GREEN}Script Glue subido correctamente.${NC}"
echo ""

echo -e "${YELLOW}=== Stack Outputs ===${NC}"
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table \
  --region "$REGION"

echo ""
echo -e "${GREEN}Despliegue completado.${NC}"
echo ""
echo "Proximos pasos:"
echo "1. Confirma tu suscripcion SNS en tu correo"
echo "2. (Opcional) Ejecuta el crawler InventarioCsvCrawler en consola Glue"
echo "3. Sube el CSV de ejemplo al bucket staging (output StagingCsvBucketName):"
echo "   aws s3 cp ../data/inventario-inicial-ejemplo.csv s3://BUCKET_STAGING/inventario-inicial-ejemplo.csv --region $REGION"
echo "4. Verifica el Glue Job CargaInventarioGlueJob en consola AWS Glue -> Runs"
echo "5. Obtén el API Key y configura el frontend"
echo "   aws apigateway get-api-key --api-key <ApiKeyId> --include-value --region $REGION"
