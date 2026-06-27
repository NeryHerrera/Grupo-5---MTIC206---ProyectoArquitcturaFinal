#!/usr/bin/env bash
# Recupera stacks fallidos, elimina buckets S3 huerfanos y despliega CloudFormation.
set -euo pipefail

: "${STACK_NAME:?STACK_NAME requerido}"
: "${TEMPLATE_FILE:?TEMPLATE_FILE requerido}"
: "${ALERT_EMAIL:?ALERT_EMAIL requerido}"

PROJECT="${PROJECT_NAME:-inventario-sme}"
UMBRAL="${STOCK_BAJO_UMBRAL:-5}"

PARAMS=(
  "ParameterKey=AlertEmail,ParameterValue=${ALERT_EMAIL}"
  "ParameterKey=ProjectName,ParameterValue=${PROJECT}"
  "ParameterKey=StockBajoUmbral,ParameterValue=${UMBRAL}"
)

stack_status() {
  aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND"
}

# Vacia y elimina un bucket S3 (incluye versionado y delete markers).
empty_s3_bucket() {
  local bucket="$1"
  if [ -z "${bucket}" ] || [ "${bucket}" = "None" ]; then
    return 0
  fi
  if ! aws s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
    echo "Bucket ${bucket} no existe."
    return 0
  fi

  echo "Vaciando s3://${bucket} ..."
  aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || true

  if aws s3 rb "s3://${bucket}" --force 2>/dev/null; then
    echo "Bucket ${bucket} eliminado."
    return 0
  fi

  local vers markers
  vers="$(aws s3api list-object-versions --bucket "${bucket}" --output json \
    --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' 2>/dev/null || echo '{}')"
  if echo "${vers}" | grep -q '"Key"'; then
    aws s3api delete-objects --bucket "${bucket}" --delete "${vers}" 2>/dev/null || true
  fi

  markers="$(aws s3api list-object-versions --bucket "${bucket}" --output json \
    --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' 2>/dev/null || echo '{}')"
  if echo "${markers}" | grep -q '"Key"'; then
    aws s3api delete-objects --bucket "${bucket}" --delete "${markers}" 2>/dev/null || true
  fi

  if aws s3 rb "s3://${bucket}" --force 2>/dev/null; then
    echo "Bucket ${bucket} eliminado (versionado)."
  else
    echo "Advertencia: no se pudo eliminar ${bucket}."
    return 1
  fi
}

# Nombres fijos definidos en inventario-sme-stack.yaml (recursos huerfanos tras DELETE_FAILED).
empty_project_s3_buckets() {
  local account_id
  account_id="$(aws sts get-caller-identity --query Account --output text)"
  empty_s3_bucket "inventario-sme-frontend-bucket-${account_id}" || true
  empty_s3_bucket "inventario-sme-staging-csv-${account_id}" || true
  empty_s3_bucket "inventario-sme-glue-assets-${account_id}" || true
}

empty_stack_s3_buckets() {
  local buckets b
  buckets="$(aws cloudformation describe-stack-resources \
    --stack-name "${STACK_NAME}" \
    --query "StackResources[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" \
    --output text 2>/dev/null || true)"
  for b in ${buckets}; do
    empty_s3_bucket "${b}" || true
  done
}

delete_stack_safe() {
  local status
  status="$(stack_status)"
  if [ "${status}" = "NOT_FOUND" ] || [ "${status}" = "None" ]; then
    return 0
  fi

  echo "Eliminando stack ${STACK_NAME} (estado: ${status}) ..."
  empty_stack_s3_buckets
  aws cloudformation delete-stack --stack-name "${STACK_NAME}"

  if aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}" 2>/dev/null; then
    echo "Stack eliminado."
    return 0
  fi

  status="$(stack_status)"
  if [ "${status}" = "DELETE_FAILED" ]; then
    echo "DELETE_FAILED: reintentando tras vaciar buckets del proyecto ..."
    empty_project_s3_buckets
    empty_stack_s3_buckets

    local failed
    failed="$(aws cloudformation describe-stack-resources \
      --stack-name "${STACK_NAME}" \
      --query "StackResources[?ResourceStatus=='DELETE_FAILED'].LogicalResourceId" \
      --output text 2>/dev/null || true)"

    if [ -n "${failed}" ]; then
      # shellcheck disable=SC2086
      aws cloudformation delete-stack \
        --stack-name "${STACK_NAME}" \
        --retain-resources ${failed}
    else
      aws cloudformation delete-stack --stack-name "${STACK_NAME}"
    fi

    aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}" 2>/dev/null || \
      echo "Advertencia: el stack puede requerir otra ejecucion del workflow."
  fi
}

recover_if_needed() {
  local status
  status="$(stack_status)"

  case "${status}" in
    DELETE_FAILED|ROLLBACK_COMPLETE|CREATE_FAILED|UPDATE_ROLLBACK_FAILED)
      echo "Stack en estado ${status}. Recuperacion automatica ..."
      delete_stack_safe
      empty_project_s3_buckets
      ;;
    NOT_FOUND|None)
      echo "Stack no existe. Limpiando buckets huerfanos del proyecto ..."
      empty_project_s3_buckets
      ;;
    CREATE_COMPLETE|UPDATE_COMPLETE|UPDATE_ROLLBACK_COMPLETE)
      echo "Stack en estado ${status}. Sin recuperacion previa."
      ;;
    *)
      echo "Stack en estado ${status}."
      ;;
  esac
}

create_stack() {
  echo "Creando ${STACK_NAME} ..."
  aws cloudformation create-stack \
    --stack-name "${STACK_NAME}" \
    --template-body "file://${TEMPLATE_FILE}" \
    --parameters "${PARAMS[@]}" \
    --capabilities CAPABILITY_NAMED_IAM

  if aws cloudformation wait stack-create-complete --stack-name "${STACK_NAME}"; then
    echo "Stack creado correctamente."
    return 0
  fi

  echo "Create fallo (revisar eventos del stack; suele ser bucket/recurso ya existente)."
  return 1
}

update_stack() {
  echo "Actualizando ${STACK_NAME} ..."
  set +e
  UPDATE_OUTPUT="$(aws cloudformation update-stack \
    --stack-name "${STACK_NAME}" \
    --template-body "file://${TEMPLATE_FILE}" \
    --parameters "${PARAMS[@]}" \
    --capabilities CAPABILITY_NAMED_IAM 2>&1)"
  UPDATE_EXIT=$?
  set -e

  if [ ${UPDATE_EXIT} -ne 0 ]; then
    if echo "${UPDATE_OUTPUT}" | grep -q "No updates are to be performed"; then
      echo "Sin cambios en la plantilla o parametros."
    else
      echo "${UPDATE_OUTPUT}"
      exit ${UPDATE_EXIT}
    fi
  else
    aws cloudformation wait stack-update-complete --stack-name "${STACK_NAME}"
    echo "Stack actualizado correctamente."
  fi
}

deploy_stack() {
  local status
  status="$(stack_status)"

  case "${status}" in
    NOT_FOUND|None)
      create_stack
      ;;
    CREATE_COMPLETE|UPDATE_COMPLETE|UPDATE_ROLLBACK_COMPLETE)
      update_stack
      ;;
    DELETE_FAILED|ROLLBACK_COMPLETE|CREATE_FAILED|UPDATE_ROLLBACK_FAILED)
      echo "Error: el stack sigue en estado ${status} tras la recuperacion."
      exit 1
      ;;
    *)
      echo "Error: estado del stack no soportado: ${status}"
      exit 1
      ;;
  esac
}

recover_if_needed

if ! deploy_stack; then
  echo "Deploy fallo. Reintentando tras recuperacion completa ..."
  recover_if_needed
  deploy_stack || exit 1
fi
