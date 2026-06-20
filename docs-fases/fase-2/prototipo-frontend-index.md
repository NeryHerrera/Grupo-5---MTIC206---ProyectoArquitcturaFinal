# Prototipo frontend — `Frontend/prototipo/index.html`

**Proyecto:** Grupo 5 — MTIC206

---

## Qué es y qué demuestra

Es una aplicación web de una sola página (HTML, CSS y JavaScript vanilla) que funciona como interfaz de demostración del sistema de inventario desplegado en AWS. No tiene backend propio: todo el procesamiento ocurre en la nube y el navegador solo envía peticiones HTTP a la API.

El prototipo demuestra el flujo completo del proyecto: ingreso de productos con visión artificial, salida de stock con alertas, consulta del inventario en vivo y autenticación mediante API Key. Sirve para pruebas locales y, una vez subido al bucket S3 del stack, como frontend de producción del sistema.

---

## Cómo funciona

Al abrir la página, el usuario configura la **URL base de la API** (outputs `ApiInvokeURL` del stack, terminada en `/prod`) y la **API Key** generada por API Gateway. Esos valores se guardan en `localStorage` del navegador para no tener que ingresarlos en cada visita.

Con la configuración lista, la aplicación ofrece tres acciones principales:

**Registrar ingreso:** el usuario selecciona o arrastra una foto del producto e indica la cantidad. JavaScript convierte la imagen a Base64 y envía un `POST` a `{apiUrl}/ingreso` con header `X-Api-Key`. API Gateway invoca la Lambda de ingreso, que usa Rekognition para identificar el objeto, lo clasifica por categoría de almacenamiento y actualiza DynamoDB. La respuesta muestra nombre, categoría, cantidad total y confianza de la IA. Tras un ingreso exitoso, se autocompleta el campo de salida con el `productoId` y se refresca el inventario.

**Registrar salida:** el usuario ingresa el `productoId` (en minúsculas, ej. `apple`) y la cantidad a retirar, o hace clic en un producto del listado. Se envía `POST` a `{apiUrl}/salida`. La Lambda resta unidades en DynamoDB y, si el stock queda bajo el umbral configurado en el stack, publica una alerta en SNS que llega al email del administrador. La interfaz indica cuántas unidades quedan y si se disparó la alerta.

**Consultar inventario:** la pestaña "Inventario Actual" llama a `GET {apiUrl}/inventario` con la API Key. La Lambda hace un Scan de DynamoDB y devuelve todos los productos con indicador de stock bajo. El listado se actualiza automáticamente tras ingresos y salidas, o manualmente con el botón Actualizar.

Además, la app mantiene un **historial local** de operaciones recientes y una pestaña de **logs de debug** en el navegador, útil durante pruebas. Estos datos viven solo en `localStorage`; no sustituyen el inventario real de DynamoDB.

---

## Recursos AWS que utiliza

El `index.html` no se conecta directamente a DynamoDB, Rekognition ni SNS. Solo habla con **API Gateway** por HTTPS. Desde ahí, la cadena de servicios es:

- **`POST /ingreso`** → Lambda `ProcesarIngresoIAFunction` → **Rekognition** (analizar imagen) + **DynamoDB** (guardar o sumar stock).
- **`POST /salida`** → Lambda `GestionarSalidasAlertasFunction` → **DynamoDB** (restar stock) + **SNS** (email si stock bajo).
- **`GET /inventario`** → Lambda `ListarInventarioFunction` → **DynamoDB** (leer inventario completo).

La autenticación la resuelve **API Gateway** validando la **API Key** en cada petición. El frontend no conoce credenciales AWS; solo la URL pública y la clave.

Para despliegue, el archivo se aloja en el **bucket S3** configurado como sitio web estático en el stack CloudFormation. El usuario accede por la URL del website de S3; las llamadas a la API salen del navegador hacia API Gateway en la misma región.

---

## Uso recomendado

Para pruebas locales conviene servir el archivo con un servidor HTTP simple (`python -m http.server`) en lugar de abrirlo con `file://`, para evitar problemas de CORS. Los valores de URL y API Key se obtienen de los outputs del stack tras el despliegue.

---

*Grupo 5 — MTIC206 — Proyecto Final de Arquitectura en la Nube*
