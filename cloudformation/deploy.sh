#!/bin/bash
# Script de despliegue rápido del stack CloudFormation
# Grupo 5 - MTIC206 - Sistema de Control de Inventario

set -e

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== CloudFormation Stack Deployment ===${NC}"
echo ""

# Validar que AWS CLI está instalado
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI no está instalado. Instálalo con: pip install awscli"
    exit 1
fi

# Variables
STACK_NAME="inventario-sme-stack"
TEMPLATE_FILE="inventario-sme-stack.yaml"
REGION="${AWS_REGION:-us-east-1}"

# Solicitar correo del administrador
read -p "Ingresa el correo del administrador (para alertas SNS): " ALERT_EMAIL

if [ -z "$ALERT_EMAIL" ]; then
    echo "Error: Correo es requerido."
    exit 1
fi

echo ""
echo -e "${YELLOW}Parámetros de despliegue:${NC}"
echo "  Stack Name: $STACK_NAME"
echo "  Template: $TEMPLATE_FILE"
echo "  Alert Email: $ALERT_EMAIL"
echo "  Region: $REGION"
echo ""

read -p "¿Continuar con el despliegue? (y/n): " CONTINUE

if [[ "$CONTINUE" != "y" ]]; then
    echo "Despliegue cancelado."
    exit 0
fi

echo ""
echo -e "${YELLOW}Iniciando despliegue...${NC}"

# Crear el stack
aws cloudformation create-stack \
  --stack-name "$STACK_NAME" \
  --template-body file://"$TEMPLATE_FILE" \
  --parameters ParameterKey=AlertEmail,ParameterValue="$ALERT_EMAIL" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$REGION" \
  --no-paginate

echo -e "${GREEN}✓ Stack creation initiated${NC}"
echo ""
echo -e "${YELLOW}Esperando a que el stack se cree completamente...${NC}"
echo "Esto puede tomar 2-5 minutos."
echo ""

# Esperar a que el stack se complete
aws cloudformation wait stack-create-complete \
  --stack-name "$STACK_NAME" \
  --region "$REGION"

echo -e "${GREEN}✓ Stack created successfully!${NC}"
echo ""

# Mostrar outputs
echo -e "${YELLOW}=== Stack Outputs ===${NC}"
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table \
  --region "$REGION"

echo ""
echo -e "${GREEN}✓ Despliegue completado exitosamente${NC}"
echo ""
echo "Próximos pasos:"
echo "1. Confirma tu suscripción al topic SNS en tu correo"
echo "2. Obtén el API Key con:"
echo "   aws apigateway get-api-key --api-key <ApiKeyId> --include-value --region $REGION"
echo "3. Carga el frontend HTML en el bucket S3"
echo "4. Prueba los endpoints /ingreso y /salida"
