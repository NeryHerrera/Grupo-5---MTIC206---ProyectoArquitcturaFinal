"""
AWS Glue ETL Job - Carga inicial de inventario CSV -> DynamoDB
Grupo 5 - MTIC206 - Inventario PyME

Extract:  Lee CSV desde S3 (bucket staging, key del evento EventBridge)
Transform: Normaliza productoId, valida categorias y cantidades (PySpark)
Load:      BatchWriteItem en DynamoDB (overwrite por productoId)

Nota POC: collect() en driver es viable para inventarios pequenos (~500 filas).
A escala mayor usar foreachPartition o conector custom hacia DynamoDB.
"""

import sys
from datetime import datetime, timezone

import boto3
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import IntegerType

CATEGORIAS_VALIDAS = ["Refrigerador", "Congelador", "Bodega Seca", "Sin Clasificar"]

args = getResolvedOptions(
    sys.argv,
    ["JOB_NAME", "TABLE_NAME", "INPUT_BUCKET", "INPUT_KEY"],
)

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
job = Job(glue_context)
job.init(args["JOB_NAME"], args)

input_bucket = args["INPUT_BUCKET"]
input_key = args["INPUT_KEY"]
table_name = args["TABLE_NAME"]
input_path = f"s3://{input_bucket}/{input_key}"

if not input_key.lower().endswith(".csv"):
    raise ValueError(f"El archivo debe ser CSV: {input_key}")

# --- Extract ---
dyf = glue_context.create_dynamic_frame.from_options(
    connection_type="s3",
    connection_options={"paths": [input_path], "recurse": False},
    format="csv",
    format_options={"withHeader": True, "separator": ","},
)

df = dyf.toDF()
total_filas = df.count()

# --- Transform ---
df = df.withColumn("productoId", F.lower(F.trim(F.col("productoId"))))
df = df.withColumn("nombre", F.trim(F.col("nombre")))
df = df.withColumn("categoria", F.trim(F.col("categoria")))
df = df.withColumn("cantidad", F.col("cantidad").cast(IntegerType()))

valid_df = df.filter(
    (F.col("productoId").isNotNull())
    & (F.col("productoId") != "")
    & (F.col("nombre").isNotNull())
    & (F.col("nombre") != "")
    & (F.col("categoria").isin(CATEGORIAS_VALIDAS))
    & (F.col("cantidad").isNotNull())
    & (F.col("cantidad") >= 0)
)

filas_validas = valid_df.count()
filas_con_error = total_filas - filas_validas
rows = valid_df.collect()

# --- Load (DynamoDB overwrite via PutItem en lotes) ---
now = datetime.now(timezone.utc).isoformat()
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(table_name)

put_requests = []
for row in rows:
    put_requests.append(
        {
            "PutRequest": {
                "Item": {
                    "productoId": row["productoId"],
                    "nombre": row["nombre"],
                    "categoria": row["categoria"],
                    "cantidad": int(row["cantidad"]),
                    "ultimaActualizacion": now,
                    "origenCarga": "ETL-CSV",
                }
            }
        }
    )

filas_procesadas = 0
for i in range(0, len(put_requests), 25):
    lote = put_requests[i : i + 25]
    pendientes = {table_name: lote}
    intentos = 0

    while pendientes and intentos < 3:
        respuesta = table.meta.client.batch_write_item(RequestItems=pendientes)
        pendientes = respuesta.get("UnprocessedItems", {})
        intentos += 1

    if pendientes:
        raise RuntimeError(
            f"No se pudieron escribir {len(pendientes.get(table_name, []))} filas tras reintentos"
        )

    filas_procesadas += len(lote)

resumen = {
    "mensaje": "ETL completado",
    "input_path": input_path,
    "filasProcesadas": filas_procesadas,
    "filasConError": filas_con_error,
}
print(resumen)

job.commit()
