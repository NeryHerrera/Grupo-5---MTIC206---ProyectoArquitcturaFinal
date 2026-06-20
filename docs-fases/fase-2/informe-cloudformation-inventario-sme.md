# Informe: Funcionamiento del Stack CloudFormation — Sistema de Control de Inventario con Visión Artificial

**Proyecto:** Grupo 5 — MTIC206  
**Archivo:** `cloudformation/inventario-sme-stack.yaml`  
**Enfoque:** Serverless en AWS (IaC)

---

## Objetivo

El stack despliega un sistema de inventario para PyMEs que permite: registrar **ingresos** con foto e identificación por IA, registrar **salidas** de stock, **consultar el inventario** desde la web y recibir **alertas por email** cuando el stock cae bajo un umbral. El frontend se sirve desde S3 y consume una API REST protegida con API Key.

Al ejecutar `create-stack` o `update-stack`, CloudFormation provisiona todos los recursos definidos en el YAML.

---

## Parámetros

- **`ProjectName`** — Prefijo de recursos (default: `inventario-sme`).
- **`AlertEmail`** — Correo del administrador para alertas SNS (debe confirmar la suscripción).
- **`StockBajoUmbral`** — Unidades mínimas antes de alertar (default: 5).

---

## Recursos principales

**S3:** bucket `FrontendBucket` como sitio web estático (`index.html`) con lectura pública. Output: `FrontendBucketWebsiteURL`.

**DynamoDB:** tabla `TablaInventarioPyME` en modo On-Demand. Clave primaria `productoId`, GSI `CategoriaIndex` por categoría, cifrado SSE activo. Almacena nombre, categoría, cantidad, fecha y confianza de la IA.

**Lambda (Node.js 24.x, rol compartido `LambdaInventoryExecutionRole`):**

- **`ProcesarIngresoIAFunction`** — `POST /ingreso`: recibe imagen Base64, la analiza con Rekognition (`DetectLabels`), asigna categoría de almacenamiento, suma stock en DynamoDB y devuelve `productoId`, nombre, categoría y cantidad total.
- **`GestionarSalidasAlertasFunction`** — `POST /salida`: resta unidades por `productoId`; si el stock queda bajo el umbral, publica alerta en SNS.
- **`ListarInventarioFunction`** — `GET /inventario`: hace Scan de la tabla, ordena por nombre y marca productos con stock bajo.

**API Gateway:** REST API `InventarioControlAPI`, stage `prod`, rutas `/ingreso`, `/salida` e `/inventario`. Todas requieren API Key (`X-Api-Key`), tienen CORS y throttling (20 req/s, ráfaga 50). Usage Plan con cuota de 30.000 llamadas/mes.

**SNS:** tópico `Alertas_StockBajo_Topic` con suscripción email al `AlertEmail`.

**IAM:** rol con mínimo privilegio — logs en CloudWatch, `DetectLabels` en Rekognition, operaciones DynamoDB en la tabla e índices, y `Publish` solo en el tópico SNS.

**CloudWatch:** log groups de las tres Lambdas con retención de 14 días. Métricas de API Gateway activas, sin access logs.

---

## Outputs

CloudFormation expone la URL del frontend S3, la URL base de la API, los endpoints `/ingreso`, `/salida` e `/inventario`, el nombre de la tabla DynamoDB, el ARN del tópico SNS y el ID de la API Key (el valor secreto se obtiene por consola o CLI).

---

## Free Tier

Lambda, API Gateway, DynamoDB, SNS y S3 encajan en las cuotas Always Free para uso moderado. Rekognition tiene 1.000 imágenes/mes gratis los primeros 12 meses; después se cobra por imagen.

---

*Grupo 5 — MTIC206 — Proyecto Final de Arquitectura en la Nube*
