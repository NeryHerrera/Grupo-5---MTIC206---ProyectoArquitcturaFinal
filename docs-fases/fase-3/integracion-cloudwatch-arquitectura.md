# Integración de Amazon CloudWatch en la Arquitectura del Sistema de Inventario

**Proyecto:** Grupo 5 — MTIC206  
**Fase:** 3 — Observabilidad y monitoreo  
**Stack:** cloudformation/inventario-sme-stack.yaml  
**Enfoque:** Serverless en AWS

---

## 1. Introducción

Amazon CloudWatch es el servicio de observabilidad de AWS. Permite centralizar registros de ejecución (logs), métricas de rendimiento y, de forma opcional, alarmas operativas sobre los recursos desplegados en la nube.

En el Sistema Automatizado de Control de Inventario con Visión Artificial, CloudWatch cumple un rol de soporte técnico y diagnóstico: permite al equipo verificar si las funciones Lambda procesan correctamente los ingresos, las salidas y las consultas de inventario, así como si el pipeline de carga inicial por CSV (AWS Glue) se ejecuta sin errores.

La propuesta original del proyecto (docs-aux/general-idea.md) establece que las métricas operativas y los registros de errores deben centralizarse en CloudWatch, de modo que un administrador técnico pueda dar soporte remoto sin administrar servidores.

Este documento describe cómo está integrado CloudWatch en la arquitectura actual, detallando cada componente implementado y las decisiones de diseño adoptadas.

---

## 2. Alcance de la implementación actual

La integración de CloudWatch en el stack es parcial y orientada al piloto académico. A continuación se indica el estado de cada capacidad:

**Implementado de forma explícita en CloudFormation**

- CloudWatch Logs (Log Groups) para las funciones Lambda principales.

**Implementado en los roles y el código**

- Permisos IAM para escritura de logs en los roles Lambda.
- Registro desde código mediante console.log y console.error en las funciones.

**Implementado en la configuración de API Gateway**

- Métricas automáticas de API Gateway (MetricsEnabled: true).

**Disponible por defecto, sin recurso adicional en CloudFormation**

- Métricas automáticas de Lambda.
- Logs automáticos de AWS Glue al ejecutar el job ETL.

**No implementado o deliberadamente omitido**

- CloudWatch Alarms (alarmas operativas automáticas).
- Dashboards de CloudWatch (vista consolidada).
- Access logs de API Gateway hacia CloudWatch (registro HTTP detallado por petición).

---

## 3. Componentes implementados

### 3.1. Log Groups explícitos para funciones Lambda

En el template CloudFormation se definen cuatro grupos de logs con retención fija de 14 días. Esta retención es una decisión consciente para controlar el volumen almacenado y mantener el consumo dentro de los límites del Free Tier de AWS (5 GB de ingesta de logs por mes en cuentas elegibles).

**Log Group: /aws/lambda/ProcesarIngresoIAFunction**

- Función Lambda asociada: ProcesarIngresoIAFunction.
- Rol en la arquitectura: registra el procesamiento de ingresos con Amazon Rekognition y la escritura en DynamoDB.

**Log Group: /aws/lambda/GestionarSalidasAlertasFunction**

- Función Lambda asociada: GestionarSalidasAlertasFunction.
- Rol en la arquitectura: registra las salidas de inventario y la publicación de alertas en Amazon SNS.

**Log Group: /aws/lambda/ListarInventarioFunction**

- Función Lambda asociada: ListarInventarioFunction.
- Rol en la arquitectura: registra las consultas al inventario (operación Scan sobre DynamoDB).

**Log Group: /aws/lambda/DispararGlueEtlFunction**

- Función Lambda asociada: DispararGlueEtlFunction.
- Rol en la arquitectura: registra los eventos de carga CSV y el inicio del job de AWS Glue.

**Definición en CloudFormation**

Cada Log Group se declara como recurso AWS::Logs::LogGroup con la propiedad RetentionInDays en 14. El recurso ProcesarIngresoLogGroup, por ejemplo, define LogGroupName como /aws/lambda/ProcesarIngresoIAFunction. El mismo patrón se repite para las otras tres funciones.

**Dependencia con las Lambdas**

Cada función Lambda declara DependsOn sobre su Log Group correspondiente. Esto garantiza que el grupo de logs exista antes de la primera invocación, evitando condiciones de carrera en el despliegue inicial.

**Qué se registra en la práctica**

- Errores capturados con console.error (fallos de Rekognition, DynamoDB, SNS o parsing del body de la petición).
- Mensajes informativos con console.log (por ejemplo, en DispararGlueEtlFunction cuando se inicia un job de Glue o se ignora un evento que no corresponde a un archivo CSV).

**Qué no se registra de forma estructurada**

- No hay formato JSON de logs ni correlación por requestId personalizado.
- Las imágenes en Base64 no se escriben en logs, lo cual es correcto desde el punto de vista de seguridad y costo.

---

### 3.2. Permisos IAM para CloudWatch Logs

Para que Lambda pueda escribir en CloudWatch Logs, los roles de ejecución incluyen permisos sobre el servicio logs. Sin estos permisos, la función no puede crear streams ni enviar eventos, y la invocación fallaría.

#### Rol LambdaInventoryExecutionRole

Este rol es compartido por las tres Lambdas de negocio del inventario. Concede los siguientes permisos:

- logs:CreateLogGroup — permite crear el grupo si aún no existiera (respaldo ante auto-creación).
- logs:CreateLogStream — abre un stream por cada contenedor de ejecución.
- logs:PutLogEvents — escribe las líneas de log generadas por la función.

El alcance del recurso es arn:aws:logs:*:*:* (patrón estándar de Lambda). Este bloque aparece en la política InventoryLambdaPolicy del template, identificado en el código como comentario "Logs en CloudWatch".

#### Rol LambdaGlueStarterRole

Usado por DispararGlueEtlFunction. Incluye los mismos tres permisos de logs, más glue:StartJobRun para iniciar el job ETL.

#### Rol LambdaGlueScriptSeedRole

Usado por GlueScriptSeedFunction (Custom Resource de CloudFormation que sube el script placeholder a S3). También incluye permisos de logs para registrar el resultado del despliegue.

**Principio aplicado**

Los permisos de logs son necesarios para el funcionamiento básico de Lambda y para diagnóstico; no constituyen un privilegio administrativo adicional sobre la infraestructura.

---

### 3.3. Registro desde el código de las funciones Lambda

Las funciones Node.js 24.x del stack utilizan la salida estándar de Node.js, que AWS redirige automáticamente a CloudWatch Logs.

**ProcesarIngresoIAFunction**

- Registro típico: console.error con el mensaje "Error en ProcesarIngresoIAFunction" y el detalle del error.
- Se genera cuando ocurre una excepción no controlada durante el ingreso con IA.

**GestionarSalidasAlertasFunction**

- Registro típico: console.error con el mensaje "Error en GestionarSalidasAlertasFunction" y el detalle del error.
- Se genera cuando falla la resta de stock o la publicación en SNS.

**ListarInventarioFunction**

- Registro típico: console.error con el mensaje "Error en ListarInventarioFunction" y el detalle del error.
- Se genera cuando falla el Scan de DynamoDB.

**DispararGlueEtlFunction**

- Registro informativo: console.log indicando que el evento fue ignorado porque no corresponde a un CSV en staging. Se genera cuando EventBridge entrega un objeto que no es archivo CSV.
- Registro informativo: console.log con el jobRunId, bucket y key cuando el job ETL se inicia correctamente.

**GlueScriptSeedFunction**

- Incluye referencia al Log Stream en la respuesta del Custom Resource de CloudFormation durante el despliegue.

**Flujo de un log de error típico (ingreso con IA)**

El frontend envía la petición a API Gateway, que invoca ProcesarIngresoIAFunction. Si ocurre un fallo en Rekognition o DynamoDB, la función ejecuta console.error. Ese mensaje se almacena en el Log Group /aws/lambda/ProcesarIngresoIAFunction. El administrador consulta ese grupo en la consola de AWS o mediante AWS CLI para identificar la causa del fallo.

---

### 3.4. Métricas de API Gateway

En el stage prod de la API REST InventarioControlAPI, la configuración de MethodSettings incluye MetricsEnabled en true, con throttling de 20 solicitudes por segundo y ráfaga de 50.

**Qué habilita MetricsEnabled: true**

Publica métricas en el namespace AWS/ApiGateway de CloudWatch, visibles en la consola sin configuración adicional. Las métricas relevantes para el proyecto son:

- Count — cantidad total de solicitudes a las rutas /ingreso, /salida e /inventario.
- 4XXError — errores del cliente (API Key inválida, body mal formado, etc.).
- 5XXError — errores del servidor (fallos internos de Lambda).
- Latency — tiempo de respuesta de la API.

**Limitación actual**

No se configuraron access logs (registro detallado de cada petición HTTP con IP, path, código de estado y latencia hacia un Log Group dedicado). Esta omisión está documentada en docs-fases/fase-2/implementacion-bd-red-almacenamiento-seguridad.md como medida para evitar un rol IAM adicional a nivel de cuenta para API Gateway y reducir el volumen de logs facturables.

La trazabilidad de la lógica de negocio se mantiene mediante los logs de las funciones Lambda, no mediante el registro de acceso de la API.

---

### 3.5. Métricas automáticas de AWS Lambda

Aunque el template no define recursos explícitos de CloudWatch para métricas Lambda, AWS publica automáticamente métricas en el namespace AWS/Lambda por cada función desplegada:

- Invocations — número de ejecuciones de la función.
- Errors — invocaciones que terminaron en error.
- Duration — tiempo de ejecución en milisegundos.
- Throttles — invocaciones rechazadas por límite de concurrencia.
- ConcurrentExecutions — ejecuciones simultáneas.

Estas métricas están disponibles en la consola de CloudWatch, sección Métricas → Lambda, asociadas a cada FunctionName del stack.

**Nota:** no se configuraron alarmas sobre estas métricas; solo están disponibles para consulta manual o futura automatización.

---

### 3.6. Logs de AWS Glue (integración automática)

El job CargaInventarioGlueJob incluye el argumento --enable-metrics: "true", lo que permite que Glue publique métricas de ejecución en CloudWatch.

Al ejecutarse el job, AWS crea y utiliza Log Groups estándar sin definirlos en CloudFormation:

- /aws-glue/jobs/output — contiene la salida estándar del script Spark/Python.
- /aws-glue/jobs/error — contiene errores y stack traces del job ETL.

Estos logs son relevantes cuando se carga el inventario inicial desde un archivo CSV en el bucket StagingCsvBucket. La guía operativa se encuentra en docs-aux/guia-carga-csv-staging.md.

**Diferencia con las Lambdas**

Los Log Groups de Glue no tienen retención de 14 días definida en el stack; aplican las políticas por defecto de la cuenta hasta que se configuren explícitamente.

---

### 3.7. Permisos de despliegue (GitHub Actions)

El archivo cloudformation/iam/github-actions-deploy-policy.json incluye un bloque CloudWatchLogGroups con permisos para:

- logs:CreateLogGroup
- logs:DeleteLogGroup
- logs:DescribeLogGroups
- logs:PutRetentionPolicy
- logs:TagLogGroup y logs:UntagLogGroup
- logs:ListTagsForResource

Esto permite que el pipeline de CI/CD cree, actualice y elimine los Log Groups definidos en el template durante operaciones de create-stack y update-stack, manteniendo la infraestructura como código.

---

## 4. Relación con otros servicios de la arquitectura

CloudWatch se integra en el flujo general de la siguiente manera:

**Capa de presentación**

El bucket S3 del frontend aloja el sitio estático. No genera logs de aplicación en CloudWatch.

**Capa de integración**

API Gateway recibe las peticiones HTTPS con X-Api-Key. Con MetricsEnabled activo, publica métricas en CloudWatch. Los access logs no están implementados.

**Capa de lógica de negocio**

Las funciones ProcesarIngresoIAFunction, GestionarSalidasAlertasFunction y ListarInventarioFunction escriben sus logs en Log Groups con retención de 14 días. AWS también publica métricas automáticas de Lambda para cada una.

**Pipeline ETL**

DispararGlueEtlFunction registra eventos en su Log Group y dispara CargaInventarioGlueJob, cuyos logs van a los grupos estándar de Glue (/aws-glue/jobs/output y /aws-glue/jobs/error).

**Servicios que no envían datos relevantes a CloudWatch en este stack**

- Amazon S3: no genera logs de aplicación en CloudWatch (existen métricas de almacenamiento a nivel de bucket, pero no están configuradas en CloudFormation).
- Amazon DynamoDB: métricas disponibles en consola, sin alarmas ni dashboards en el template.
- Amazon Rekognition: no tiene Log Group propio; los resultados y errores se registran en la Lambda que lo invoca.
- Amazon SNS: las alertas de stock bajo van por correo electrónico, no por CloudWatch Alarms.

---

## 5. Componentes no implementados (brecha respecto a observabilidad completa)

**CloudWatch Alarms**

No hay alertas automáticas por errores en Lambda o respuestas 5xx en la API. Como recomendación futura, se podrían agregar una o dos alarmas que notifiquen al tópico SNS ya existente.

**Dashboards de CloudWatch**

No existe una vista consolidada de salud del sistema. Se recomienda, en una fase posterior, crear un dashboard con invocaciones, errores y latencia.

**Access logs de API Gateway**

No hay registro HTTP detallado por petición. Conviene evaluarlo solo si el proyecto requiere auditoría de acceso.

**Retención explícita en logs de Glue**

Sin configuración en el stack, los logs ETL podrían acumularse. Se recomienda definir RetentionInDays: 14 en los Log Groups de Glue.

**Log Group para GlueScriptSeedFunction**

El log group se crea automáticamente en la primera ejecución. Opcionalmente, podría declararse en CloudFormation por consistencia con el resto de las funciones.

---

## 6. Consulta operativa de CloudWatch

Una vez desplegado el stack, los Log Groups pueden consultarse desde:

- Consola AWS: CloudWatch → Log groups → filtrar por /aws/lambda/
- Consola Lambda: seleccionar la función → Monitor → View logs in CloudWatch

**Comandos de referencia (AWS CLI)**

Para listar los log groups de las Lambdas del proyecto:

aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/" --query "logGroups[*].{Nombre:logGroupName,Retencion:retentionInDays}"

Para ver logs recientes de la función de ingreso (últimos 30 minutos):

aws logs tail "/aws/lambda/ProcesarIngresoIAFunction" --since 30m

Para ver logs del disparador ETL en tiempo real:

aws logs tail "/aws/lambda/DispararGlueEtlFunction" --follow

Para listar métricas de API Gateway:

aws cloudwatch list-metrics --namespace "AWS/ApiGateway" --dimensions Name=ApiName,Value=InventarioControlAPI

---

## 7. Consideraciones de costo (Free Tier)

Según la estimación documentada en cloudformation/README.md:

**Ingesta de logs**

- Límite Free Tier de referencia: 5 GB por mes.
- Uso estimado del piloto: aproximadamente 500 MB por mes.

**Retención**

- Configurado en CloudFormation: 14 días.
- Efecto: controla la acumulación de logs y evita costos innecesarios.

**Métricas estándar**

- Incluidas para API Gateway y Lambda.
- Sin costo adicional en el uso estimado del piloto.

**Alarmas**

- Free Tier: 10 alarmas de métricas sin costo.
- Estado actual: 0 alarmas configuradas.

La retención de 14 días en los Log Groups de Lambda es la principal medida de control de costos adoptada en la arquitectura actual.

---

## 8. Conclusión

Amazon CloudWatch está integrado de forma funcional y deliberada en la arquitectura serverless del proyecto, con énfasis en:

1. Centralización de logs de las cuatro funciones Lambda relevantes, con retención acotada a 14 días.
2. Permisos IAM mínimos para escritura de logs en todos los roles de ejecución.
3. Métricas de API Gateway habilitadas para monitoreo de tráfico y errores HTTP.
4. Métricas automáticas de Lambda disponibles sin configuración adicional.
5. Logs de Glue accesibles al ejecutar la carga inicial por CSV.

La implementación es adecuada para un piloto académico y una PyME en etapa inicial: permite diagnosticar fallos, revisar ejecuciones del ETL y observar el comportamiento de la API, sin incurrir en la complejidad ni el costo de alarmas, dashboards o access logs completos.

Las alertas de stock bajo del negocio se gestionan mediante Amazon SNS (correo al administrador), no mediante CloudWatch Alarms. Ambos mecanismos son complementarios: SNS cubre reglas de negocio; CloudWatch cubre salud técnica de la infraestructura.

---

Grupo 5 — MTIC206 — Proyecto Final de Arquitectura en la Nube
