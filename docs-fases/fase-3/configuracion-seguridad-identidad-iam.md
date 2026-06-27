# Configuración de Seguridad e Identidad (IAM, Roles, Políticas)

**Proyecto:** Grupo 5 — MTIC206  
**Fase:** 3 — Seguridad e identidad en la nube  
**Stack:** cloudformation/inventario-sme-stack.yaml  
**Enfoque:** Serverless en AWS

---

## 1. Introducción

AWS Identity and Access Management (IAM) es el servicio que administra identidades y permisos dentro de una cuenta de AWS. Permite definir quién o qué servicio puede ejecutar una acción, sobre qué recurso y bajo qué condiciones.

En el Sistema Automatizado de Control de Inventario con Visión Artificial, la seguridad no se basa en credenciales embebidas en el código ni en usuarios humanos operando las Lambdas. Cada componente de cómputo (funciones Lambda, jobs de Glue) asume un rol IAM con permisos acotados. El acceso desde el exterior se controla mediante API Key en API Gateway y políticas de bucket en S3.

La propuesta original del proyecto (docs-aux/general-idea.md) contemplaba un rol LambdaInventoryExecutionRole con permisos de mínimo privilegio para DynamoDB, Rekognition y SNS. La implementación actual cumple ese diseño y lo extiende con roles adicionales para el pipeline ETL (Glue), el despliegue automatizado (GitHub Actions con OIDC) y la autenticación de la API REST.

Este documento describe cómo está configurada la seguridad e identidad en la arquitectura desplegada, detallando cada rol, política y mecanismo de control de acceso.

---

## 2. Principios de seguridad aplicados

El stack adopta las siguientes directrices:

**Principio de mínimo privilegio**

Cada rol recibe únicamente los permisos necesarios para su función. Por ejemplo, la Lambda de ingreso no puede publicar en tópicos SNS arbitrarios ni escribir en buckets S3.

**Identidad por servicio, no por usuario**

Las Lambdas y los jobs de Glue operan con roles de servicio (trust policy hacia lambda.amazonaws.com o glue.amazonaws.com). No se utilizan access keys de IAM dentro del código de aplicación.

**Separación de responsabilidades por rol**

Existen roles distintos para la lógica de inventario, el disparo del ETL, la siembra del script Glue y la ejecución del crawler. Un compromiso en una función no otorga automáticamente todos los permisos del sistema.

**Defensa en profundidad**

La protección se articula en varias capas: políticas de bucket S3, API Key en API Gateway, permisos granulares en IAM, cifrado en reposo en DynamoDB y throttling para limitar abuso.

**Infraestructura como código**

Roles, políticas inline y asociaciones de permisos se declaran en CloudFormation, lo que permite auditar, versionar y reproducir la configuración de seguridad.

---

## 3. Roles IAM definidos en el stack

El template CloudFormation provisiona cinco roles IAM con nombre fijo (requiere CAPABILITY_NAMED_IAM en el despliegue). A continuación se describe cada uno.

### 3.1. LambdaInventoryExecutionRole

**Propósito:** rol de ejecución compartido por las tres funciones Lambda de negocio del inventario.

**Funciones que lo utilizan:**

- ProcesarIngresoIAFunction (ingreso con visión artificial)
- GestionarSalidasAlertasFunction (salidas y alertas)
- ListarInventarioFunction (consulta de inventario)

**Trust policy (quién puede asumir el rol):**

- Principal: lambda.amazonaws.com
- Acción: sts:AssumeRole

Solo el servicio Lambda de AWS puede asumir este rol. Ningún usuario, aplicación externa ni otro servicio puede hacerlo directamente.

**Política inline: InventoryLambdaPolicy**

La política concede cuatro bloques de permisos:

**Bloque 1 — CloudWatch Logs**

- logs:CreateLogGroup
- logs:CreateLogStream
- logs:PutLogEvents
- Recurso: arn:aws:logs:*:*:*

Permite escribir logs de ejecución. Es un requisito operativo de Lambda.

**Bloque 2 — Amazon Rekognition**

- rekognition:DetectLabels
- Recurso: * (todas las regiones)

Limitado exclusivamente a la operación de detección de etiquetas en imágenes. No incluye reconocimiento facial, moderación de contenido ni otras APIs de Rekognition.

**Bloque 3 — Amazon DynamoDB**

- dynamodb:PutItem, GetItem, UpdateItem, Query, Scan
- Recursos acotados:
  - ARN de la tabla TablaInventarioPyME
  - ARN del índice secundario global (patrón /index/*)

No incluye dynamodb:DeleteItem ni permisos sobre otras tablas de la cuenta.

**Bloque 4 — Amazon SNS**

- sns:Publish
- Recurso: ARN específico del tópico Alertas_StockBajo_Topic

No puede publicar en otros tópicos SNS de la cuenta.

**Permisos explícitamente ausentes**

Este rol no tiene acceso a S3, Glue, CloudFormation, IAM ni administración de infraestructura. Si una de las tres Lambdas de inventario fuera comprometida, el impacto quedaría limitado al inventario, a Rekognition DetectLabels y a las alertas del tópico configurado.

---

### 3.2. LambdaGlueStarterRole

**Propósito:** rol de ejecución de DispararGlueEtlFunction, la Lambda que inicia el job ETL cuando se sube un CSV al bucket de staging.

**Trust policy:**

- Principal: lambda.amazonaws.com
- Acción: sts:AssumeRole

**Política inline: StartGlueJobAndLogs**

**Permisos de logs:**

- logs:CreateLogGroup, CreateLogStream, PutLogEvents
- Recurso: arn:aws:logs:*:*:*

**Permiso de Glue:**

- glue:StartJobRun
- Recurso acotado al job CargaInventarioGlueJob en la región y cuenta del stack

No puede modificar la definición del job, crear otros jobs ni acceder a DynamoDB directamente. Su única acción de negocio es disparar una ejecución del job ETL configurado.

---

### 3.3. LambdaGlueScriptSeedRole

**Propósito:** rol de ejecución de GlueScriptSeedFunction, una Lambda Custom Resource que sube un script placeholder de Python al bucket de assets de Glue durante el despliegue de CloudFormation.

**Trust policy:**

- Principal: lambda.amazonaws.com
- Acción: sts:AssumeRole

**Política inline: SeedGlueScriptPolicy**

**Permisos de logs:**

- logs:CreateLogGroup, CreateLogStream, PutLogEvents

**Permiso de S3:**

- s3:PutObject
- Recurso acotado: GlueAssetsBucket/scripts/* (solo la ruta de scripts)

No puede leer ni borrar objetos, ni escribir en otros buckets. El alcance está restringido a la siembra inicial del script ETL.

**Permiso de invocación (recurso separado):**

GlueScriptSeedFunctionPermission autoriza a cloudformation.amazonaws.com a invocar la función durante create-stack y update-stack.

---

### 3.4. GlueCrawlerRole

**Propósito:** rol que utiliza InventarioCsvCrawler para descubrir el esquema de archivos CSV en el bucket de staging.

**Trust policy:**

- Principal: glue.amazonaws.com
- Acción: sts:AssumeRole

**Política administrada de AWS:**

- arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole

Concede permisos base que Glue necesita para operar el crawler (CloudWatch Logs, Glue Data Catalog, etc.).

**Política inline: GlueCrawlerStagingPolicy**

- s3:GetObject, s3:ListBucket
- Recursos acotados al StagingCsvBucket y sus objetos

El crawler solo puede leer el bucket de staging CSV. No tiene acceso al bucket del frontend ni al bucket de assets de Glue.

---

### 3.5. GlueEtlExecutionRole

**Propósito:** rol de ejecución del job CargaInventarioGlueJob (ETL Spark que carga CSV hacia DynamoDB).

**Trust policy:**

- Principal: glue.amazonaws.com
- Acción: sts:AssumeRole

**Política administrada de AWS:**

- arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole

**Política inline: GlueEtlCustomPolicy**

**Lectura en S3:**

- s3:GetObject, s3:ListBucket
- Recursos: StagingCsvBucket, GlueAssetsBucket y sus objetos

**Escritura temporal en S3:**

- s3:PutObject
- Recurso acotado: GlueAssetsBucket/temp/* (directorio temporal del job Spark)

**Escritura en DynamoDB:**

- dynamodb:PutItem, dynamodb:BatchWriteItem
- Recursos: TablaInventarioPyME y su índice secundario

No incluye operaciones de lectura, actualización ni eliminación en DynamoDB. El job solo inserta o sobrescribe mediante batch write.

**Lectura en Glue Data Catalog:**

- glue:GetDatabase, glue:GetTable, glue:GetTables
- Recursos acotados al catálogo, la base inventario_sme_staging y sus tablas

---

## 4. Políticas de recursos y permisos entre servicios

Además de los roles IAM, el stack define políticas sobre recursos específicos y permisos de invocación cruzada entre servicios.

### 4.1. Política del bucket frontend (FrontendBucketPolicy)

**Tipo:** AWS::S3::BucketPolicy

**Efecto:** Allow

**Principal:** * (cualquier identidad anónima o autenticada en Internet)

**Acción:** s3:GetObject

**Recurso:** objetos dentro del FrontendBucket (inventario-sme-frontend-bucket-{AccountId}/*)

**Justificación:** el frontend es un sitio web estático que debe ser accesible públicamente para que el personal de bodega abra la aplicación desde el navegador. Solo se permite lectura de objetos; no hay permiso de escritura pública.

**Configuración complementaria del bucket:**

- PublicAccessBlock deshabilitado en las cuatro opciones (permite la política pública de lectura).
- CORS configurado para GET desde cualquier origen.

**Riesgo mitigado:** el bucket no almacena datos de inventario ni secretos. La información sensible permanece detrás de la API autenticada con API Key.

---

### 4.2. Buckets privados (StagingCsvBucket y GlueAssetsBucket)

**Configuración de PublicAccessBlock:** las cuatro opciones en true (BlockPublicAcls, BlockPublicPolicy, IgnorePublicAcls, RestrictPublicBuckets).

No tienen política de acceso público. Solo los roles IAM autorizados (GlueCrawlerRole, GlueEtlExecutionRole, LambdaGlueScriptSeedRole) pueden interactuar con ellos según los permisos definidos en sus respectivas políticas.

El StagingCsvBucket además habilita EventBridgeConfiguration para notificar eventos de creación de objetos sin exponer el bucket a Internet.

---

### 4.3. Permisos de invocación Lambda (resource-based policies)

Estos recursos AWS::Lambda::Permission definen qué servicios externos pueden invocar cada función. Actúan como políticas basadas en recurso sobre la Lambda.

**IngresoLambdaPermission**

- Principal: apigateway.amazonaws.com
- Acción: lambda:InvokeFunction
- Función: ProcesarIngresoIAFunction
- SourceArn acotado: POST /ingreso de InventarioControlAPI

**SalidaLambdaPermission**

- Principal: apigateway.amazonaws.com
- Acción: lambda:InvokeFunction
- Función: GestionarSalidasAlertasFunction
- SourceArn acotado: POST /salida de InventarioControlAPI

**InventarioLambdaPermission**

- Principal: apigateway.amazonaws.com
- Acción: lambda:InvokeFunction
- Función: ListarInventarioFunction
- SourceArn acotado: GET /inventario de InventarioControlAPI

**DispararGlueEtlEventPermission**

- Principal: events.amazonaws.com
- Acción: lambda:InvokeFunction
- Función: DispararGlueEtlFunction
- SourceArn acotado: regla EventBridge InventarioCsvUploadRule

**GlueScriptSeedFunctionPermission**

- Principal: cloudformation.amazonaws.com
- Acción: lambda:InvokeFunction
- Función: GlueScriptSeedFunction

**Efecto de SourceArn:** API Gateway solo puede invocar cada Lambda desde la ruta HTTP específica. EventBridge solo puede invocar DispararGlueEtlFunction desde la regla configurada. Esto reduce el riesgo de invocación no autorizada desde otros APIs o reglas de la cuenta.

---

## 5. Autenticación y control de acceso en API Gateway

La capa de integración implementa autenticación del cliente mediante API Key, complementada con throttling y cuotas de uso.

### 5.1. API Key (InventarioApiKey)

**Recurso:** AWS::ApiGateway::ApiKey

**Nombre:** InventarioControlAPIKey

**Estado:** Enabled (true)

**Asociación:** vinculada al stage prod de InventarioControlAPI mediante StageKeys.

**Uso en el cliente:** el frontend debe enviar el header X-Api-Key en cada petición a /ingreso, /salida e /inventario.

**Métodos protegidos:**

- POST /ingreso — ApiKeyRequired: true
- POST /salida — ApiKeyRequired: true
- GET /inventario — ApiKeyRequired: true

**Métodos OPTIONS (CORS):** ApiKeyRequired no aplica; AuthorizationType: NONE. Permiten el preflight del navegador sin clave.

**AuthorizationType en todos los métodos de datos:** NONE (no hay Cognito, Lambda authorizer ni IAM auth). La única barrera de autenticación es la API Key.

**Limitación reconocida:** la API Key es un secreto compartido, no identifica usuarios individuales. No reemplaza un sistema de login con roles (bodeguero, gerente). Es adecuada para un prototipo con frontend controlado, pero no para escenarios con múltiples actores y auditoría por usuario.

**Gestión del secreto:** el valor de la API Key no se expone en los Outputs del stack (solo el ApiKeyId). Debe obtenerse por consola AWS o CLI y configurarse en el frontend o en variables de entorno, sin commitearla al repositorio.

---

### 5.2. Usage Plan (InventarioUsagePlan)

**Recurso:** AWS::ApiGateway::UsagePlan

**Nombre:** InventarioControlUsagePlan

**API asociada:** InventarioControlAPI, stage prod

**Throttling:**

- RateLimit: 20 solicitudes por segundo (sostenido)
- BurstLimit: 50 solicitudes (ráfaga)

**Cuota mensual:**

- Limit: 30.000 invocaciones
- Period: MONTH

**Vinculación de clave:** InventarioUsagePlanKey asocia InventarioApiKey al plan.

**Propósito de seguridad operativa:** limita abuso accidental o malicioso que podría elevar costos o agotar cuotas del Free Tier. Actúa como barrera de rate limiting a nivel de API Gateway.

---

### 5.3. Throttling adicional en el stage

El recurso ApiStage también define MethodSettings con ThrottlingRateLimit: 20 y ThrottlingBurstLimit: 50 para todos los métodos (ResourcePath: /*, HttpMethod: *). Refuerza el control de tráfico a nivel de stage.

---

## 6. Protección de datos y cifrado

### 6.1. Datos en reposo

**DynamoDB (TablaInventarioPyME):**

- SSESpecification con SSEEnabled: true
- Cifrado server-side administrado por AWS sobre la tabla de inventario

**S3:**

- Los buckets no declaran cifrado explícito en el template. AWS aplica cifrado SSE-S3 por defecto en buckets nuevos desde enero de 2023.

**Imágenes de producto:**

- No se persisten en S3 ni DynamoDB. Se procesan en memoria en la Lambda y solo se almacena el resultado semántico (nombre, categoría, cantidad, confianza).

---

### 6.2. Datos en tránsito

- Comunicación navegador → API Gateway: HTTPS (endpoint estándar de execute-api).
- Comunicación API Gateway → Lambda: canal interno de AWS.
- Lambda → DynamoDB, Rekognition, SNS: endpoints de servicio AWS, no expuestos públicamente.

El website endpoint de S3 puede servirse por HTTP según configuración del bucket; en producción se recomienda evaluar CloudFront con HTTPS, aunque no está implementado en el stack actual.

---

### 6.3. Notificaciones SNS

**Tópico:** Alertas_StockBajo_Topic

**Suscripción:** protocolo email al parámetro AlertEmail

**Confirmación obligatoria:** AWS envía un correo de confirmación al administrador. Hasta que no se acepte la suscripción, no se reciben alertas. Esto evita envíos no deseados a direcciones configuradas por error.

**Permiso de publicación:** solo LambdaInventoryExecutionRole (vía GestionarSalidasAlertasFunction) puede publicar en este tópico, y únicamente cuando el stock cae bajo el umbral configurado.

---

## 7. Identidad para despliegue automatizado (CI/CD)

El repositorio incluye configuración IAM para GitHub Actions, separada del stack de aplicación pero relevante para la gobernanza de la infraestructura.

### 7.1. Trust policy OIDC (github-oidc-trust-policy.json)

Define cómo GitHub Actions asume un rol IAM en AWS sin access keys permanentes.

**Principal federado:** token.actions.githubusercontent.com (OIDC provider de GitHub)

**Acción:** sts:AssumeRoleWithWebIdentity

**Condiciones:**

- token.actions.githubusercontent.com:aud debe ser sts.amazonaws.com
- token.actions.githubusercontent.com:sub debe coincidir con repo:GITHUB_ORG/GITHUB_REPO:ref:refs/heads/main

Solo el workflow del repositorio y rama configurados puede asumir el rol de despliegue.

---

### 7.2. Política de despliegue (github-actions-deploy-policy.json)

Política de permisos amplia para que el pipeline pueda crear, actualizar y eliminar recursos del stack. Incluye bloques para:

- CloudFormation (create/update/delete stack, change sets)
- IAM (crear roles con nombre, attach/detach policies, PassRole)
- S3 (buckets frontend, staging, glue-assets)
- DynamoDB (create/update/delete table)
- Lambda (create/update/delete functions, permissions)
- API Gateway (operaciones REST)
- SNS (topics y suscripciones)
- CloudWatch Log Groups
- Rekognition DetectLabels

**Alcance de recursos:** la mayoría de statements usan Resource: * (amplio). Esto es habitual en roles de CI/CD de cuentas dedicadas a desarrollo, pero implica que el rol de despliegue tiene privilegios elevados comparado con los roles de runtime de la aplicación.

**Despliegue del stack:** el workflow deploy-infrastructure.yml invoca create-stack y update-stack con --capabilities CAPABILITY_NAMED_IAM, necesario porque los roles tienen RoleName fijo.

**Secretos en GitHub:**

- ALERT_EMAIL (secret): correo para suscripción SNS, no se commitea al repo
- AWS_ROLE_ARN (variable): ARN del rol OIDC de despliegue

---

## 8. Resumen de roles y funciones

**LambdaInventoryExecutionRole**

- Asumido por: ProcesarIngresoIAFunction, GestionarSalidasAlertasFunction, ListarInventarioFunction
- Acceso a: CloudWatch Logs, Rekognition DetectLabels, DynamoDB TablaInventarioPyME, SNS Alertas_StockBajo_Topic

**LambdaGlueStarterRole**

- Asumido por: DispararGlueEtlFunction
- Acceso a: CloudWatch Logs, glue:StartJobRun en CargaInventarioGlueJob

**LambdaGlueScriptSeedRole**

- Asumido por: GlueScriptSeedFunction
- Acceso a: CloudWatch Logs, s3:PutObject en GlueAssetsBucket/scripts/*

**GlueCrawlerRole**

- Asumido por: InventarioCsvCrawler
- Acceso a: AWSGlueServiceRole (managed), lectura S3 en StagingCsvBucket

**GlueEtlExecutionRole**

- Asumido por: CargaInventarioGlueJob
- Acceso a: AWSGlueServiceRole (managed), lectura S3 staging y assets, escritura temp en Glue, BatchWriteItem en DynamoDB, lectura Glue Data Catalog

---

## 9. Componentes de seguridad no implementados

**Autenticación de usuarios finales**

No hay Amazon Cognito, login de empleados ni JWT. La API Key es compartida por todo el frontend.

**Autorización por rol de negocio**

No se distingue entre bodeguero y gerente a nivel de API. Cualquier cliente con la API Key puede invocar ingreso, salida e inventario.

**AWS WAF**

No hay filtrado de tráfico web malicioso delante de API Gateway.

**VPC y endpoints privados**

La arquitectura es completamente pública serverless, sin aislamiento de red mediante VPC.

**Rotación automática de API Key**

La clave se genera una vez en el despliegue. No hay mecanismo de rotación periódica en el template.

**AWS KMS con claves propias**

DynamoDB usa SSE administrado por AWS; no hay CMK (Customer Managed Key) definida en el stack.

**Access logs de API Gateway**

Omitidos para no requerir rol adicional y reducir volumen de logs (documentado en fase 2).

---

## 10. Conclusión

La configuración de seguridad e identidad del proyecto se apoya en un modelo de roles IAM especializados con permisos acotados por servicio y recurso. Las tres Lambdas de inventario comparten un rol restrictivo que solo alcanza logs, Rekognition DetectLabels, la tabla DynamoDB del proyecto y el tópico SNS de alertas. El pipeline ETL utiliza roles Glue y Lambda separados con acceso limitado a los buckets de staging y assets, y escritura controlada en DynamoDB.

En el perímetro externo, API Gateway exige API Key en todas las rutas de negocio, complementada con throttling y cuota mensual. S3 expone públicamente solo el frontend estático, mientras que los buckets de datos y scripts permanecen privados. DynamoDB cifra datos en reposo y las imágenes de producto no se almacenan.

El despliegue automatizado mediante GitHub OIDC elimina access keys permanentes en el pipeline, aunque el rol de CI/CD mantiene privilegios amplios propios de la gestión de infraestructura.

La implementación es coherente con un piloto académico y una PyME en etapa inicial: equilibra simplicidad operativa con mínimo privilegio en runtime. Para producción con múltiples usuarios, auditoría por persona y cumplimiento normativo más estricto, sería necesario evolucionar hacia Cognito, rotación de secretos, WAF y posiblemente access logs con retención controlada.

---

Grupo 5 — MTIC206 — Proyecto Final de Arquitectura en la Nube
