Propuesta de arquitectura en AWS: Sistema Automatizado de Control de Inventario con Visión Artificial
1. Descripción del Problema y Justificación Empresarial
En el sector gastronómico y de pequeñas y medianas empresas (PyMEs) dedicadas al catering, el manejo ineficiente de los inventarios representa una de las principales fuentes de pérdidas económicas. El registro manual de insumos en bodegas es un proceso lento, propenso a errores humanos y que frecuentemente resulta en la caducidad de productos no detectados a tiempo o, por el contrario, en el desabastecimiento durante horas de alta demanda.
Para resolver esta problemática, el presente proyecto propone el diseño e implementación de un Sistema Automatizado de Control de Inventario basado en una arquitectura Serverless en la nube de AWS. La solución elimina la fricción operativa al permitir que el personal de bodega simplemente tome una fotografía de los insumos al momento de recibirlos. Utilizando servicios de Inteligencia Artificial (visión por computadora), el sistema identificará el producto, lo categorizará (ej. refrigeración, alacena seca, limpieza) y actualizará la base de datos de inventario en tiempo real, emitiendo alertas automatizadas cuando los niveles de stock alcancen umbrales críticos.
2. Objetivos del Proyecto
Objetivo General: Diseñar, documentar e implementar una infraestructura distribuida y Serverless en AWS, utilizando exclusivamente la capa gratuita, para automatizar la recepción, categorización y control de inventario de una PyME gastronómica mediante el análisis de imágenes.
Objetivos Específicos:
Desplegar y configurar una arquitectura basada en microservicios utilizando Amazon S3, API Gateway, AWS Lambda, Amazon DynamoDB y Amazon Rekognition.
Implementar un flujo de reconocimiento de imágenes que permita identificar y clasificar productos sin intervención manual de digitación.
Establecer mecanismos de notificación automatizada (mediante Amazon SNS) para alertar sobre niveles bajos de inventario.
Garantizar la viabilidad económica del proyecto asegurando que todos los recursos se mantengan dentro de los límites del Free Tier de AWS.
3. Arquitectura Propuesta y Servicios AWS
La solución se basa en una arquitectura de tres capas (Presentación, Lógica e Integración, y Datos) completamente Serverless, lo que garantiza alta disponibilidad, escalabilidad automática y costos de mantenimiento reducidos. A continuación, se detallan los servicios seleccionados y su rol específico dentro de la solución:
Servicio AWS
Capa Arquitectónica
Función y Justificación Técnica
 
Amazon S3
Presentación (Frontend)
Actuará como el servicio de alojamiento (hosting estático) para el prototipo de la aplicación web (HTML/JS/CSS). Se elige S3 por su alta durabilidad y capacidad de servir contenido estático con latencia mínima y costo nulo bajo demanda.
Amazon API Gateway
Integración
Funcionará como el punto de entrada RESTful (Endpoint) seguro. Recibirá las peticiones HTTP/POST enviadas desde el frontend con la carga útil (imagen del producto) y las enrutará hacia el backend para su procesamiento.
AWS Lambda
Lógica de Negocio (Backend)
Ejecutará el código subyacente sin necesidad de administrar servidores. Se crearán funciones para: 1) Recibir la imagen e invocar la API de IA, 2) Procesar las respuestas y escribir en base de datos, y 3) Gestionar las reducciones de inventario y disparar alertas.
Amazon Rekognition
Inteligencia Artificial
Servicio central de visión artificial. Analizará la fotografía del insumo, detectando objetos (Labels). Su justificación radica en la eliminación del ingreso manual de datos, acelerando y automatizando el proceso de recepción en bodega.
Amazon DynamoDB
Persistencia de Datos
Base de datos NoSQL clave-valor. Almacenará el catálogo de productos (id, nombre, categoría de almacenamiento, cantidad actual). Su modelo On-Demand es ideal para patrones de tráfico irregulares de una bodega, ajustándose a la capa gratuita.
Amazon SNS
Notificaciones y Automatización
Simple Notification Service (SNS) se encargará de publicar mensajes y enviar correos electrónicos automatizados al administrador cuando el stock de un producto crítico caiga por debajo del nivel mínimo establecido.


4. Diagrama de arquitectura propuesto

5. Flujo Operativo del Sistema
El ciclo de vida de la información, desde la recepción del producto hasta su registro y posterior consumo, se describe en las siguientes etapas:
Captura y Envío: El usuario, a través de la interfaz web alojada en S3, captura o sube la fotografía del producto recién recibido del proveedor. La aplicación web realiza un POST request hacia el endpoint expuesto por Amazon API Gateway.
Intercepción y Orquestación: API Gateway desencadena de forma síncrona la función Lambda configurada, pasándole la imagen como payload.
Análisis Cognitivo: La función Lambda invoca la operación "DetectLabels" de Amazon Rekognition. Rekognition procesa la imagen y devuelve una lista estructurada (JSON) con las etiquetas identificadas y su nivel de confianza (ej. "Vegetal: 98%").
Clasificación Lógica: La función Lambda procesa la respuesta de Rekognition. Mediante un mapeo predefinido en el código, asocia la etiqueta principal a una categoría de almacenamiento (ej. si es "Vegetal", la categoría es "Refrigerador").
Registro de Inventario: La misma función Lambda se conecta a Amazon DynamoDB. Si el producto ya existe, actualiza el atributo de cantidad sumando las nuevas unidades. Si no existe, crea un nuevo registro con la categoría identificada.
Consumo y Alertamiento (Salida): Cuando un empleado retira un producto de la bodega, reporta la salida mediante el portal web. Esto invoca otra ruta de API Gateway que actualiza DynamoDB restando la cantidad. Si el nuevo valor es menor a un umbral configurado (ej. < 5 unidades), la Lambda publica un mensaje en un Topic de Amazon SNS, el cual envía un correo de alerta al gerente para su pronta reposición.
6. Consideraciones de la Capa Gratuita (Free Tier) y Análisis Económico
Este diseño asegura una viabilidad económica total (costo $0) durante el periodo de evaluación y desarrollo del proyecto, basándose en los siguientes límites de la capa gratuita de AWS:
Amazon S3: 5 GB de almacenamiento estándar, 20,000 solicitudes GET y 2,000 solicitudes PUT por mes. Suficiente para alojar y servir la aplicación web estática.
API Gateway: 1 millón de llamadas a la API REST por mes.
AWS Lambda: 1 millón de solicitudes gratuitas y 400,000 GB-segundos de tiempo de computación por mes.
Amazon Rekognition: Análisis de 5,000 imágenes por mes durante los primeros 12 meses, margen amplio para realizar todas las pruebas de concepto.
Amazon DynamoDB: 25 GB de almacenamiento y 25 unidades de capacidad de lectura/escritura aprovisionadas.
Amazon SNS: 1,000 notificaciones por correo electrónico al mes.
FASE 1: DISEÑO E IMPLEMENTACIÓN DE ARQUITECTURA EN AWS
1. Descripción del Problema, Empresa y Objetivos
1.1. Descripción del Problema y de la Empresa
Propuesta: “Sistema Automatizado de Control de Inventario con Visión Artificial”.
El proyecto se enfoca en el sector gastronómico y de pequeñas y medianas empresas (PyMEs) dedicadas al catering y preparación de alimentos. En este tipo de empresas, los insumos representan el activo circulante más crítico y, al mismo tiempo, el más difícil de controlar debido a su naturaleza perecedera.
Actualmente, la empresa enfrenta graves ineficiencias operativas debido a que el registro de ingresos y egresos a bodega se realiza de forma manual o mediante hojas de cálculo rudimentarias. Esto genera tres problemas principales:
Pérdidas Económicas por Caducidad: Insumos costosos se vencen en el fondo de la alacena o refrigeradores al no existir un sistema de rotación eficiente ni alertas preventivas.
Quiebres de Stock: Desabastecimiento de ingredientes clave durante las horas de alta demanda, lo que paraliza la cocina o cancela pedidos, afectando la reputación del negocio.
Fricción Operativa: El personal de bodega gasta tiempo valioso digitando códigos, nombres y cantidades, un proceso propenso a errores humanos (errores de dedo, transcripciones incorrectas).

1.2. Objetivos del Proyecto
Objetivo General: Diseñar, documentar e implementar una infraestructura distribuida y Serverless en AWS, utilizando exclusivamente la capa gratuita (Free Tier), para automatizar la recepción, categorización y control de inventario de una PyME gastronómica mediante el análisis de imágenes por computadora.
Objetivos Específicos:
Desplegar y configurar una arquitectura basada en microservicios utilizando Amazon S3, API Gateway, AWS Lambda, Amazon DynamoDB y Amazon Rekognition.
Implementar un flujo de reconocimiento de imágenes que permita identificar y clasificar productos automáticamente sin intervención manual de digitación.
Establecer mecanismos de notificación automatizada (mediante Amazon SNS) para alertar sobre niveles bajos de inventario en tiempo real.
Garantizar la viabilidad económica del proyecto asegurando que todos los recursos se mantengan estrictamente dentro de los límites del Free Tier de AWS.
2. Análisis de Factibilidad
2.1. Factibilidad Técnica
La solución planteada es técnicamente viable debido al uso del paradigma Serverless (Sin Servidores) en AWS. Esto elimina la necesidad de aprovisionar, parchar o mantener sistemas operativos o servidores virtuales (como EC2).
La justificación técnica de los servicios seleccionados demuestra una integración nativa y de baja latencia:
Amazon S3: Permite el alojamiento seguro de la interfaz web (frontend) con un 99.999999999% de durabilidad, eliminando la necesidad de un servidor web dedicado.
Amazon API Gateway: Maneja de forma segura las peticiones HTTP concurrentes procedentes de los clientes web y realiza la integración síncrona con la lógica de cómputo.
AWS Lambda: Ejecuta el código backend de manera aislada y bajo demanda. Se autoescala instantáneamente según el volumen de solicitudes entrantes de la bodega.
Amazon Rekognition: Aporta las capacidades de Inteligencia Artificial mediante modelos ya entrenados por Amazon. La función DetectLabels permite extraer metadatos de las imágenes en milisegundos con alta precisión, evitando que la empresa tenga que entrenar y desplegar un modelo propio de Machine Learning.
Amazon DynamoDB: Base de datos NoSQL que ofrece latencias de un solo dígito de milisegundo. Su flexibilidad de esquema permite almacenar productos con atributos variables sin penalizaciones de rendimiento.
Amazon SNS: Garantiza el desacoplamiento de las alertas. La función Lambda solo publica el evento de stock bajo y SNS se encarga de distribuirlo, permitiendo añadir múltiples canales de alerta en el futuro (SMS, Webhooks) sin modificar el código base.


2.2. Factibilidad Económica
El proyecto está diseñado bajo un modelo de Costo $0 USD para la etapa de desarrollo, pruebas y puesta en marcha inicial (Piloto), apalancando al 100% las condiciones de la Capa Gratuita (AWS Free Tier).
A continuación, se presenta la estimación y verificación del uso mensual frente a los límites permitidos:

Servicio AWS
Límite Mensual Capa Gratuita (Free Tier)
Uso Mensual Estimado (PyME Piloto)
Estado de Viabilidad
Amazon S3
5 GB de almacenamiento / 2,000 PUTs / 20,000 GETs
< 500 MB (Código Web) / 1,000 PUTs / 5,000 GETs
Cubierto (Costo $0)
Amazon API Gateway
1 Millón de llamadas a la API REST
~15,000 llamadas al mes (Ingresos y salidas)
Cubierto (Costo $0)
AWS Lambda
1 Millón de peticiones / 400,000 GB-segundos
~15,000 peticiones / ~15,000 GB-segundos
Cubierto (Costo $0)
Amazon Rekognition
5,000 imágenes analizadas por mes (Primeros 12 meses)
~3,000 imágenes (Nuevos ingresos a bodega)
Cubierto (Costo $0)
Amazon DynamoDB
25 GB de almacenamiento / 25 WCU y 25 RCU
< 100 MB de datos / < 5 WCU - RCU promedio
Cubierto (Costo $0)
Amazon SNS
1,000 notificaciones por correo electrónico
~200 correos de alertas de stock bajo
Cubierto (Costo $0)


Conclusión Económica: El riesgo financiero es inexistente durante el periodo de evaluación, y los costos posteriores se escalarán proporcionalmente bajo la modalidad de "Pago por uso", manteniendo márgenes extremadamente bajos e idóneos para una PyME.
2.3. Factibilidad Operativa
Factores de Implementación: El despliegue de la infraestructura se puede automatizar por completo mediante herramientas de Infraestructura como Código (IaC) o directamente a través de la consola de AWS de forma ágil, reduciendo los tiempos de salida a producción a pocos días.
Usuarios del Sistema: El usuario principal es el Personal de Bodega (Bodeguero). El sistema mitiga la resistencia al cambio tecnológico mediante una interfaz ultra-simplificada: en lugar de llenar formularios web complejos, la operación clave se reduce a encender la cámara del dispositivo móvil, capturar la foto del producto y presionar "Enviar".
Soporte y Monitoreo: Al ser una arquitectura Serverless, las tareas de administración de infraestructura son nulas. AWS se encarga de la alta disponibilidad y redundancia geográfica. Las métricas operativas y los registros de errores se centralizan automáticamente en AWS CloudWatch, facilitando que un único administrador técnico pueda dar soporte remoto al sistema.

3. Diagrama de Arquitectura Propuesta
La arquitectura sigue un flujo desacoplado y estructurado en capas. Para cargarlo visualmente en herramientas como Draw.io, utiliza el código XML que generamos en el paso anterior. Estructuralmente, la organización se define de la siguiente manera:
Capa de Presentación: Una aplicación Web SPA (Single Page Application) construida en HTML5, JavaScript y CSS3, alojada en un bucket de Amazon S3 configurado para Static Web Hosting. Los usuarios interactúan aquí desde teléfonos móviles o tablets en la bodega.
Capa de Integración: Las peticiones HTTP (POST) que llevan los datos del inventario o las imágenes codificadas en Base64 golpean un endpoint seguro en Amazon API Gateway, el cual valida las solicitudes y las mapea hacia los servicios internos.
Capa de Lógica de Negocio: Dividida en dos microservicios principales basados en AWS Lambda:
Lambda de Ingresos: Recibe la imagen, invoca la IA, procesa las etiquetas resultantes (JSON) e incrementa el stock.
Lambda de Salidas: Registra las reducciones de inventario de forma manual y evalúa las reglas de negocio (umbrales mínimos).
Capa de Inteligencia Artificial: Amazon Rekognition analiza las características visuales de los insumos usando visión computacional y le devuelve los metadatos de clasificación a la Lambda de forma síncrona.
Capa de Datos: Un almacén NoSQL transaccional en Amazon DynamoDB que mantiene la persistencia del catálogo e inventarios operativos en tiempo real.
Capa de Notificaciones: Un tópico de Amazon SNS que se dispara de manera asíncrona cuando se detectan alertas críticas de inventario, enviando correos electrónicos inmediatos al Gerente del Restaurante.

4. Lista de Servicios AWS Planificados
A continuación se detalla la lista final de recursos y servicios que serán aprovisionados en la plataforma de AWS para la puesta en marcha de la solución:
Servicio AWS
Nombre del Componente / Recurso
Tipo / Configuración
Función Específica en la Solución
Amazon S3
inventario-sme-frontend-bucket
Almacenamiento Estándar (Hosting Web activado)
Alojar los archivos estáticos de la interfaz de usuario para acceso de los operarios.
Amazon API Gateway
InventarioControlAPI
REST API
Exponer las rutas públicas /ingreso y /salida para conectar el frontend con el backend.
AWS Lambda
ProcesarIngresoIAFunction
Runtime: Python 3.11 (o Node.js)
Recibir la imagen, llamar a Rekognition, interpretar las etiquetas y guardar el registro.
AWS Lambda
GestionarSalidasAlertasFunction
Runtime: Python 3.11 (o Node.js)
Restar stock en la Base de Datos y evaluar si se debe disparar una alerta a SNS.
Amazon Rekognition
Servicio Global (API)
Operación: DetectLabels
Analizar los objetos de las fotografías enviadas para deducir el tipo de insumo (vegetales, carnes, limpieza).
Amazon DynamoDB
TablaInventarioPyME
Tabla NoSQL (Llave Primaria: id_producto)
Almacenar las cantidades actuales, nombres, categorías y umbrales de stock mínimo de los insumos.
Amazon SNS
AlertasStockBajoTopic
Tópico Estándar (Suscripción tipo Email)
Enrutar y despachar los correos electrónicos automáticos de alerta hacia el Administrador/Gerente.
AWS IAM
LambdaInventoryExecutionRole
Roles y Políticas de Seguridad
Garantizar que las funciones Lambda tengan permisos de menor privilegio para escribir en DynamoDB, invocar a Rekognition y publicar en SNS.


