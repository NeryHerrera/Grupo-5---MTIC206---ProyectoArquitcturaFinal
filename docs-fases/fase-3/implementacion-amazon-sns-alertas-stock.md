# Implementación de Amazon SNS — Alertas de Stock Bajo

**Proyecto:** Grupo 5 — MTIC206  
**Stack:** cloudformation/inventario-sme-stack.yaml

---

Amazon SNS envía un correo al administrador cuando el stock de un producto queda por debajo de un umbral mínimo. Solo actúa en el flujo de **salidas de bodega**; no interviene en ingresos con IA, consultas de inventario ni carga por CSV.

**Flujo:** el frontend llama POST /salida → GestionarSalidasAlertasFunction resta unidades en DynamoDB → si la cantidad restante es menor al umbral, publica en SNS → el correo llega al AlertEmail configurado. El navegador no accede a SNS; la API responde con alertaDisparada para informar en pantalla.

**Infraestructura (CloudFormation):** tópico Alertas_StockBajo_Topic y suscripción email al parámetro AlertEmail. El umbral se define con StockBajoUmbral (default: 5) y llega a la Lambda como UMBRAL_STOCK_BAJO. Tras desplegar el stack hay que **confirmar la suscripción** en el correo de AWS; sin eso no llegan alertas.

**Lógica de disparo:** alerta cuando stock restante < umbral (ej. con umbral 5, stock 4 sí alerta, stock 5 no). Cada salida bajo el umbral genera un correo; no hay deduplicación.

**Seguridad:** el rol LambdaInventoryExecutionRole solo tiene sns:Publish sobre el ARN de ese tópico.

**Limitaciones:** umbral global para todos los productos, un solo correo destino, solo canal email, alertas únicamente en salidas manuales.

**Free Tier:** ~200 correos/mes estimados, dentro del límite de 1.000/mes.

---

Grupo 5 — MTIC206 — Proyecto Final de Arquitectura en la Nube
