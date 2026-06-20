# Implementación de bases de datos, red, almacenamiento y seguridad

**Proyecto:** Grupo 5 — MTIC206  
**Stack:** `cloudformation/inventario-sme-stack.yaml`

---

## Bases de datos

La capa de persistencia del sistema se implementa con **Amazon DynamoDB**, servicio de base de datos NoSQL totalmente administrado por AWS. La tabla principal se denomina `TablaInventarioPyME` y concentra todo el inventario de la PyME: productos registrados, cantidades en stock, categorías de almacenamiento y metadatos de las operaciones.

La tabla utiliza el modo de facturación **On-Demand** (pago por solicitud). En este modelo no es necesario provisionar capacidad de lectura o escritura de antemano; DynamoDB escala automáticamente según el volumen de peticiones que generen las funciones Lambda. Esto resulta adecuado para cargas variables propias de un prototipo o una PyME con tráfico intermitente, y se alinea con las cuotas del Free Tier de AWS.

La clave primaria de la tabla es el atributo `productoId`, de tipo cadena de texto. Este identificador se genera en la lógica de ingreso a partir del nombre detectado por Rekognition, normalizado a minúsculas. Por ejemplo, si la IA identifica "Apple", el registro se almacena bajo el identificador `apple`. Esta decisión garantiza unicidad por producto y facilita las operaciones de salida, donde el usuario o el frontend referencian el artículo por su ID.

Además de la clave primaria, la tabla define un **Índice Secundario Global** (GSI) llamado `CategoriaIndex`, indexado por el atributo `categoria`. Este índice proyecta todos los atributos del ítem y permite, en evoluciones futuras del sistema, consultar productos agrupados por zona de almacenamiento (Refrigerador, Congelador, Bodega Seca, etc.) sin recorrer la tabla completa. En la implementación actual, la función de listado utiliza una operación `Scan` sobre la tabla principal, suficiente para inventarios de tamaño reducido.

Cada registro almacena, entre otros campos, el nombre legible del producto, la categoría asignada, la cantidad disponible, la fecha de última actualización y el porcentaje de confianza que devolvió Rekognition al momento del ingreso. Las operaciones de escritura las ejecutan las Lambdas de ingreso y salida mediante `UpdateItem` y `GetItem`; la Lambda de consulta utiliza `Scan` para recuperar el inventario completo.

La seguridad de los datos en reposo se refuerza con **cifrado SSE** habilitado a nivel de tabla (`SSEEnabled: true`), de modo que la información permanece cifrada en los discos de DynamoDB sin gestión adicional de claves por parte del equipo de desarrollo.

---

## Red

La conectividad del sistema se apoya en servicios gestionados de AWS que exponen endpoints HTTPS públicos, sin necesidad de desplegar una VPC, subredes, balanceadores ni instancias EC2. Este enfoque serverless simplifica la operación y reduce costos de infraestructura de red.

El punto de entrada principal para la lógica de negocio es **Amazon API Gateway** en modalidad **REST API regional**. La API se llama `InventarioControlAPI` y se publica en el stage `prod`, generando una URL del tipo `https://{api-id}.execute-api.{region}.amazonaws.com/prod`. Desde esa URL base se accede a tres rutas: `/ingreso` (POST), `/salida` (POST) e `/inventario` (GET).

API Gateway actúa como proxy entre el cliente HTTP y las funciones Lambda. Cada método está configurado con integración `AWS_PROXY`, lo que significa que la petición completa del usuario se reenvía a la Lambda correspondiente y la respuesta de la Lambda se devuelve tal cual al cliente. Este patrón es estándar en arquitecturas serverless y evita transformaciones manuales de request/response en la capa de API.

Para permitir que el frontend, alojado en un dominio distinto (S3 website u origen local durante pruebas), consuma la API desde el navegador, se configuró **CORS** en cada recurso. Los métodos OPTIONS responden con encabezados que autorizan orígenes amplios (`Access-Control-Allow-Origin: *`), los métodos HTTP permitidos y el header personalizado `X-Api-Key`. Las propias Lambdas también incluyen el header CORS en sus respuestas JSON.

El control de tráfico se implementa mediante **throttling** en el stage de API Gateway: un límite sostenido de 20 peticiones por segundo y una ráfaga de 50. Adicionalmente, un **Usage Plan** fija una cuota mensual de 30.000 invocaciones. Estas medidas protegen la API frente a picos accidentales o uso excesivo, contribuyendo a mantener el consumo dentro de los límites del Free Tier.

La capa de presentación se sirve por una vía de red separada: el **website endpoint** de S3, que expone el frontend estático por HTTP/HTTPS propio del bucket. El frontend se comunica con API Gateway exclusivamente por HTTPS, enviando la API Key en cada solicitud. No existe comunicación directa del navegador hacia DynamoDB, Rekognition ni SNS; todo el tráfico de datos pasa por la API y las Lambdas, lo que concentra el control de acceso en un único punto.

Las funciones Lambda se ejecutan dentro de la red administrada de AWS y acceden a DynamoDB, Rekognition y SNS mediante endpoints de servicio internos, sin exposición pública de la base de datos ni de los servicios de backend.

---

## Almacenamiento

El almacenamiento del proyecto se divide en dos tipos según la naturaleza de los datos: archivos estáticos de interfaz y datos estructurados de inventario.

Para la **interfaz de usuario**, se provisiona un bucket S3 denominado `inventario-sme-frontend-bucket-{AccountId}`. El bucket está configurado como **sitio web estático**, con `index.html` como documento de entrada y `error.html` como página de error. Esta configuración permite hospedar la aplicación frontend sin un servidor web dedicado: el propio servicio S3 resuelve las peticiones GET de los archivos HTML, CSS y JavaScript.

El acceso al contenido estático se habilita mediante una **política de bucket** que concede permiso público de lectura (`s3:GetObject`) a cualquier principal. Solo los objetos del bucket son legibles; no se permite escritura pública. El bucket incluye además reglas CORS para solicitudes GET desde cualquier origen, coherente con un frontend que puede consultarse desde distintos entornos durante el desarrollo.

Los **datos de negocio** (productos, cantidades, categorías, timestamps) no residen en S3 sino exclusivamente en DynamoDB, como se describe en la sección de bases de datos. S3 cumple únicamente la función de almacenamiento de presentación; la fuente de verdad del inventario es la tabla `TablaInventarioPyME`.

Las **imágenes de producto** que el usuario sube desde el frontend no se persisten en S3 ni en DynamoDB. Se convierten a Base64 en el navegador, se envían en el cuerpo de la petición POST a `/ingreso` y la Lambda las procesa en memoria para enviarlas a Rekognition. Tras el análisis, solo se guarda el resultado semántico (nombre, categoría, cantidad), no el archivo binario de la fotografía. Esta decisión reduce costos de almacenamiento y simplifica el modelo de datos, aunque implica que las fotografías originales no quedan archivadas para auditoría.

Los **logs de ejecución** de las Lambdas se almacenan en Amazon CloudWatch Logs, en grupos con retención explícita de 14 días. Esta política evita acumulación indefinida de logs, que podría generar costos fuera del Free Tier en cuentas de desarrollo o demostración.

---

## Seguridad

La seguridad del stack se articula en varios niveles: identidad y permisos (IAM), autenticación de clientes (API Key), protección de datos en tránsito y reposo, y notificaciones acotadas al ámbito del proyecto.

### Identidad y permisos (IAM)

Todas las funciones Lambda comparten un único rol de ejecución: `LambdaInventoryExecutionRole`. El rol confía únicamente en el servicio `lambda.amazonaws.com` para asumirlo, siguiendo el principio de que cada recurso de cómputo opera con una identidad propia y no con credenciales de usuario embebidas.

La política adjunta al rol concede permisos mínimos estrictamente necesarios:

- Escritura de logs en CloudWatch, indispensable para diagnóstico y obligatoria para el funcionamiento básico de Lambda.
- Invocación de `rekognition:DetectLabels` sobre cualquier recurso, limitada a la API de etiquetado de imágenes y no a otras capacidades de Rekognition (reconocimiento facial, moderación de video, etc.).
- Operaciones de lectura y escritura en la tabla DynamoDB `TablaInventarioPyME` y en su índice secundario: `PutItem`, `GetItem`, `UpdateItem`, `Query` y `Scan`.
- Publicación de mensajes únicamente en el tópico SNS `Alertas_StockBajo_Topic`, identificado por su ARN concreto y no en tópicos arbitrarios de la cuenta.

Ninguna Lambda recibe permisos de administración, acceso a S3, ni capacidad de modificar la infraestructura CloudFormation. Si una función fuera comprometida, el blast radius quedaría acotado a inventario y alertas del proyecto.

### Autenticación de la API

Los endpoints de API Gateway no son completamente abiertos. Cada método exige una **API Key** válida (`ApiKeyRequired: true`). El frontend debe incluir el header `X-Api-Key` en todas las peticiones. La clave se genera como recurso `InventarioApiKey` y se asocia al stage `prod` mediante un Usage Plan.

Este mecanismo no reemplaza un sistema de identidad de usuarios finales (no hay login de empleados ni JWT), pero impide que cualquier actor anónimo invoque la API si desconoce la clave. Para un prototipo académico o una PyME con frontend controlado, resulta un equilibrio razonable entre simplicidad y protección básica.

### Protección de datos

Las comunicaciones entre el navegador y API Gateway, y entre API Gateway y Lambda, transiten por HTTPS en la práctica de despliegue estándar de AWS. DynamoDB cifra los datos en reposo con SSE. Las API Keys deben tratarse como secretos: se obtienen una vez del stack o de la consola y se configuran en el frontend sin publicarlas en repositorios de código.

La suscripción SNS por correo requiere **confirmación explícita** del destinatario. Hasta que el administrador no acepte la suscripción desde el enlace enviado por AWS, no recibirá alertas, lo que evita envíos no deseados a direcciones configuradas por error.

### Seguridad operativa y de costos

El throttling y la cuota del Usage Plan actúan como barrera ante abuso o bucles de llamadas que podrían elevar la factura o agotar cuotas gratuitas.

Los Log Groups con retención de 14 días limitan la exposición prolongada de información de depuración en CloudWatch.

Se omitió el logging de acceso de API Gateway (access logs hacia CloudWatch) para no exigir un rol adicional a nivel de cuenta y para reducir volumen de logs facturables. La trazabilidad de la lógica de negocio se mantiene mediante los logs de las Lambdas.

El bucket S3 del frontend es de lectura pública por diseño, coherente con un sitio estático. No almacena datos sensibles de inventario; la información crítica permanece detrás de la API autenticada.

---

## Conclusión

La implementación combina DynamoDB como base de datos escalable y cifrada, API Gateway como capa de red y control de tráfico, S3 como almacenamiento estático del frontend, e IAM más API Key como pilares de seguridad. El diseño evita infraestructura de red tradicional (VPC, NAT, EC2) apoyándose en servicios serverless gestionados, lo que reduce complejidad operativa y mantiene el sistema dentro de un perfil de costos acorde al Free Tier y al alcance de una PyME.

*Grupo 5 — MTIC206 — Proyecto Final de Arquitectura en la Nube*
