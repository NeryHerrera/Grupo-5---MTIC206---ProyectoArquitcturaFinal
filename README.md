# Grupo 5 - MTIC206 - Proyecto Final

# Propuesta de arquitectura en AWS: Sistema Automatizado de Control de Inventario con Visión Artificial

## 1. Descripción del Problema y Justificación Empresarial
El proyecto se enfoca en el sector gastronómico y en las pequeñas y medianas empresas (PyMEs) que se dedican al catering y preparación de alimentos. En este tipo de negocios, el manejo ineficiente de los inventarios es una fuente principal de pérdidas económicas, ya que los insumos perecederos son el activo más crítico y difícil de controlar.

Actualmente, las empresas enfrentan ineficiencias porque el registro en bodega se hace de forma manual o con hojas de cálculo rudimentarias. Esto genera tres problemas principales:
* **Pérdidas económicas por caducidad:** Los insumos se vencen al no existir un sistema preventivo de rotación.
* **Quiebres de stock:** Ocurre desabastecimiento en horas de alta demanda, lo que paraliza la cocina.
* **Fricción operativa:** El personal pierde tiempo digitando datos y cometiendo errores humanos.

**La Solución:** Se propone un Sistema Automatizado de Control de Inventario con arquitectura Serverless en AWS. El personal de bodega solo necesita tomar una fotografía de los insumos al recibirlos. Usando Inteligencia Artificial (visión por computadora), el sistema identifica, categoriza y actualiza la base de datos en tiempo real, emitiendo alertas cuando el inventario es crítico. Esta acción simplificada mitiga la resistencia al cambio tecnológico.

---

## 2. Objetivos del Proyecto

### Objetivo General
Diseñar, documentar e implementar una infraestructura distribuida y Serverless en AWS, utilizando de forma exclusiva la capa gratuita (Free Tier), para automatizar la recepción, categorización y control de inventario mediante el análisis de imágenes por computadora.

### Objetivos Específicos
* Desplegar una arquitectura basada en microservicios empleando Amazon S3, API Gateway, AWS Lambda, Amazon DynamoDB y Amazon Rekognition.
* Implementar un flujo de reconocimiento de imágenes que identifique y clasifique los productos automáticamente, sin intervención manual de digitación.
* Establecer notificaciones automatizadas en tiempo real mediante Amazon SNS para alertar sobre niveles bajos de inventario.
* Asegurar la viabilidad económica manteniendo todos los recursos estrictamente dentro de los límites del Free Tier de AWS.

---

## 3. Arquitectura Propuesta y Capas de Servicio

La solución emplea una arquitectura Serverless de tres capas (Presentación, Lógica e Integración, y Datos) que garantiza alta disponibilidad, autoescalabilidad y reducción de costos de mantenimiento. Las tareas operativas y registros de errores se centralizan en AWS CloudWatch.

### Componentes de la Arquitectura

| Servicio AWS | Capa Arquitectónica | Función Específica |
| :--- | :--- | :--- |
| **Amazon S3** | Presentación (Frontend) | Funciona como alojamiento estático web (HTML5/JS/CSS3) para la aplicación. Ofrece 99.999999999% de durabilidad y latencia mínima a costo nulo. Nombre del recurso: `inventario-sme-frontend-bucket`. |
| **Amazon API Gateway** | Integración | Punto de entrada seguro RESTful que recibe las peticiones HTTP/POST con la imagen (Base64) y las enruta al backend. Nombre del recurso: `InventarioControlAPI` exponiendo rutas `/ingreso` y `/salida`. |
| **AWS Lambda** | Lógica de Negocio (Backend) | Ejecuta el código de manera aislada y autoescalable sin administrar servidores. Existen dos microservicios: `ProcesarIngresoIAFunction` (invoca a Rekognition y guarda datos) y `GestionarSalidasAlertasFunction` (resta inventario y dispara alertas) construidas en Python 3.11 o Node.js. |
| **Amazon Rekognition** | Inteligencia Artificial | Servicio de visión computacional. Utiliza la operación `DetectLabels` para extraer metadatos y deducir el tipo de insumo en milisegundos de forma síncrona, eliminando la necesidad de entrenar un modelo propio. |
| **Amazon DynamoDB** | Persistencia de Datos | Base de datos NoSQL clave-valor (tabla `TablaInventarioPyME`). Almacena cantidades, nombres y categorías mediante un modelo On-Demand, ideal para flujos irregulares con baja latencia. |
| **Amazon SNS** | Notificaciones y Automatización | Servicio estándar que publica y distribuye de forma asíncrona correos electrónicos automatizados al administrador mediante el tópico `Alertas_StockBajo_Topic`. |
| **AWS IAM** | Seguridad | Administra permisos a través del rol `LambdaInventoryExecutionRole`, garantizando que Lambda tenga privilegios mínimos para usar servicios internos. |

---

## 4. Flujo Operativo del Sistema

El ciclo de vida de la información se describe en las siguientes etapas:

1.  **Captura y Envío:** El usuario usa la web alojada en S3 para tomar o subir la foto del producto; la web envía un request POST a API Gateway.
2.  **Intercepción y Orquestación:** API Gateway desencadena de forma síncrona la función Lambda, pasándole la imagen.
3.  **Análisis Cognitivo:** Lambda invoca `DetectLabels` de Amazon Rekognition, que devuelve un JSON con etiquetas y niveles de confianza.
4.  **Clasificación Lógica:** Lambda mapea la etiqueta principal a una categoría de almacenamiento (ej. "Vegetal" a "Refrigerador").
5.  **Registro de Inventario:** Lambda se conecta a DynamoDB; suma unidades si el producto existe o crea un registro nuevo si no existe.
6.  **Consumo y Alertamiento:** Para salidas, el empleado reporta el retiro en la web, invocando a API Gateway y Lambda para restar la cantidad. Si el nivel es menor al umbral, Lambda publica en un Topic de Amazon SNS que envía un correo al gerente.

---

## 5. Análisis de Factibilidad

### Factibilidad Técnica
El uso del paradigma Serverless suprime la necesidad de mantener sistemas operativos o servidores virtuales como EC2. La arquitectura permite despliegue automatizado con Infraestructura como Código (IaC) o por medio de la consola ágil de AWS. AWS garantiza la redundancia geográfica y alta disponibilidad.

### Factibilidad Económica (Capa Gratuita / Free Tier)
El modelo asegura un costo de $0 USD para la evaluación y desarrollo inicial, con el siguiente análisis de uso mensual estimado:

| Servicio AWS | Límite Mensual Capa Gratuita | Uso Mensual Estimado | Viabilidad |
| :--- | :--- | :--- | :--- |
| **Amazon S3** | 5 GB almacenamiento / 2,000 PUTS / 20,000 GETS | < 500 MB / 1,000 PUTS / 5,000 GETS | Cubierto ($0) |
| **API Gateway** | 1 Millón llamadas API REST | ~15,000 llamadas al mes | Cubierto ($0) |
| **AWS Lambda** | 1 Millón peticiones / 400,000 GB-segundos | ~15,000 peticiones / ~15,000 GB-s | Cubierto ($0) |
| **Amazon Rekognition** | 5,000 imágenes al mes (primeros 12 meses) | ~3,000 imágenes (ingresos a bodega) | Cubierto ($0) |
| **Amazon DynamoDB**| 25 GB almacenamiento / 25 WCU y 25 RCU | < 100 MB datos / < 5 WCU-RCU promedio | Cubierto ($0) |
| **Amazon SNS** | 1,000 notificaciones por correo | ~200 correos de alerta de stock bajo | Cubierto ($0) |

**Conclusión Económica:** El riesgo financiero es inexistente durante la evaluación; posteriormente funciona con el modelo de "Pago por uso" adecuado para PyMEs.
