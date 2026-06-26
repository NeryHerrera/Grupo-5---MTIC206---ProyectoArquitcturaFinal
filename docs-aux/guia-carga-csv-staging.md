# Guía: Carga manual del CSV de inventario inicial en AWS (AWS Glue ETL)

Esta guía describe los pasos en la **consola web de AWS** para subir el archivo CSV al bucket de staging y poblar DynamoDB mediante **AWS Glue** (job Spark ETL disparado por EventBridge).

**Prerequisitos:**

- Stack CloudFormation `inventario-sme-stack` desplegado con recursos Glue.
- Script Glue subido a `GlueAssetsBucket` (automático con `deploy.sh` o manual, ver paso 0).
- Archivo CSV con formato estándar (ver [`data/inventario-inicial-ejemplo.csv`](../data/inventario-inicial-ejemplo.csv)).

**Formato del CSV:**

```csv
productoId,nombre,categoria,cantidad
banana,Platano,Refrigerador,24
```

Categorías permitidas: `Refrigerador`, `Congelador`, `Bodega Seca`, `Sin Clasificar`.

**Comportamiento al re-subir:** la cantidad se **sobrescribe** por `productoId`. El ETL Glue **no** dispara alertas SNS.

---

## Paso 0: Confirmar script Glue en S3 (solo si no usaste deploy.sh)

1. **CloudFormation** → stack `inventario-sme-stack` → **Outputs** → copia `GlueAssetsBucketName`.
2. **S3** → abre ese bucket → verifica que exista `scripts/carga_inventario_etl.py`.
3. Si no existe, súbelo desde tu equipo o ejecuta:

   ```bash
   aws s3 cp glue/scripts/carga_inventario_etl.py s3://GLUE_ASSETS_BUCKET/scripts/carga_inventario_etl.py --region us-east-1
   ```

---

## Paso 1: Obtener el nombre del bucket staging

1. Inicia sesión en [AWS Management Console](https://console.aws.amazon.com/).
2. Confirma la **región** donde desplegaste el stack (ej. `us-east-1`).
3. **CloudFormation** → stack **`inventario-sme-stack`** → pestaña **Outputs**.
4. Copia **`StagingCsvBucketName`** (ej. `inventario-sme-staging-csv-123456789012`).

---

## Paso 2 (opcional): Ejecutar el Crawler Glue

Demuestra el descubrimiento de esquema en el Data Catalog:

1. Busca **AWS Glue** en la barra de servicios.
2. Menú **Data catalog** → **Crawlers**.
3. Selecciona **`InventarioCsvCrawler`** → **Run**.
4. Espera estado **Succeeded** (opcional antes de la primera carga; el job ETL lee el CSV directamente por ruta S3).

---

## Paso 3: Subir el archivo CSV al bucket staging

1. **S3** → abre el bucket `StagingCsvBucketName` (no el de frontend ni el de Glue assets).
2. Pestaña **Objects** → **Upload**.
3. Selecciona el CSV (ej. `inventario-inicial-ejemplo.csv`).
4. Verifica que el nombre termine en **`.csv`**.
5. **Upload** → espera **Succeeded**.

Al completarse la carga, **EventBridge** detecta el evento `Object Created` y lanza el Glue Job **`CargaInventarioGlueJob`** con los parámetros `--INPUT_BUCKET` y `--INPUT_KEY`.

---

## Paso 4: Verificar ejecución del Glue Job

1. **AWS Glue** → menú **ETL jobs**.
2. Abre **`CargaInventarioGlueJob`**.
3. Pestaña **Runs** → la ejecución más reciente debe pasar a **Succeeded** (1–3 minutos).
4. Haz clic en el **Run ID** → revisa **Logs** → **Output logs** (CloudWatch).
5. Busca el resumen: `mensaje: ETL completado`, `filasProcesadas`, `filasConError`.

Si el run falla con error de script no encontrado, repite el **Paso 0**.

Log groups útiles en **CloudWatch**:

- `/aws-glue/jobs/output`
- `/aws-glue/jobs/error`

---

## Paso 5: Verificar datos en DynamoDB

1. **DynamoDB** → **Tables** → **`TablaInventarioPyME`**.
2. **Explore table items**.
3. Confirma productos del CSV, incluyendo **`banana`** con `origenCarga: ETL-CSV`.

---

## Paso 6 (opcional): Verificar desde la API

1. Copia **`InventarioEndpoint`** y **`ApiKeyId`** desde CloudFormation Outputs.
2. Obtén la API Key:

   ```bash
   aws apigateway get-api-key --api-key TU_API_KEY_ID --include-value --region us-east-1
   ```

3. Consulta inventario:

   ```bash
   curl -H "X-Api-Key: TU_API_KEY" "https://TU_API.execute-api.us-east-1.amazonaws.com/prod/inventario"
   ```

---

## Notas importantes

- **EventBridge**, no Lambda: el disparador es la regla `InventarioCsvUploadRule`, no una función Lambda.
- **Re-carga:** subir un CSV actualizado vuelve a ejecutar el Glue Job y sobrescribe cantidades.
- **Costo:** cada ejecución Spark usa ~2 workers G.1X (~2 DPU-min); adecuado para POC.
- **Stack previo con Lambda ETL:** actualiza con `update-stack` antes de probar; CloudFormation reemplaza la Lambda por Glue.
