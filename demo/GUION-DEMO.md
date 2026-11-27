# Guion de la demo: AWS DevOps Agent

**Duración:** 60 min · **Agent Space:** `Demo-Agent` (en español) · **Audiencia:** equipo de operación y desarrollo del cliente

## La idea central (dila al inicio y al cierre)

> "Hoy ustedes pasan horas buscando *por qué* falló algo, y se enteran *después* de que llegó a producción. DevOps Agent hace dos cosas: **encuentra la causa raíz por ustedes**, cruzando logs, infraestructura, despliegues y código, y **prueba los cambios antes de que lleguen a producción**."

Los tres dolores que mencionó el cliente, y la demo que responde a cada uno:

| Dolor del cliente | Demo | Qué van a ver |
|---|---|---|
| "Nos cuesta encontrar la causa raíz de errores en el código" | **D1** | De un error 500 al commit y la línea exacta, con plan de rollback |
| "Los batch legados fallan por configuración y nadie sabe por qué" | **D2** | De una alarma al archivo de configuración que cambió |
| "No sabemos si una app va a funcionar tras un ajuste" | **D3** | Un cambio que pasa los tests y que el agente detiene antes de producción |

---

## Apertura (5 min)

**Mostrar:** consola de DevOps Agent → `Demo-Agent` → web app.

**Decir:**
- "Este es un *Agent Space*: el espacio donde el agente conoce su entorno. Lo conectamos a la cuenta de AWS y al repositorio de GitHub. No instalamos agentes en los servidores."
- "Habla español, y usa permisos de solo lectura: investiga sin tocar nada."

**Mostrar rápido:** la pestaña de topología. "El agente descubrió solo qué recursos existen y cómo se conectan: el cluster, el balanceador, la instancia del batch."

---

## D1: Error en el código (15 min)

### El escenario, en una frase
"Un desarrollador agregó una mejora a los pedidos. Los tests pasaron, se desplegó, y de pronto **ningún cliente puede comprar**."

### Qué hacer
1. Mostrar el error: en el navegador, la tienda devuelve error al hacer *Checkout*.
2. Mostrar que Kubernetes dice que todo está bien: el pod está `Running` y `Ready`. "Su monitoreo actual probablemente tampoco alertaría."
3. Abrir la investigación ya hecha: **"POST /api/orders del servicio shop devuelve HTTP 500 en cluster-test"**.
   - Para mostrar cómo se lanza, escribe en el chat: *"Los pedidos de la tienda en cluster-test están fallando con error 500, ¿qué pasó?"*

### Qué encontró el agente (resultado real)
- **Síntoma:** el 100% de los pedidos falla desde las 14:24:39, pero el resto de la API funciona.
- **Causa raíz:** línea 57 de `server.js` (`items[0].meta.label`). El campo `meta` no lo envía ni el frontend ni el contrato de la API (`openapi.yaml`). **El agente leyó el código del repositorio para confirmarlo.**
- **Quién y cuándo:** a las 14:23:59 se desplegó a mano una rama de un PR sin aprobar. Lo sacó de los logs de auditoría de Kubernetes.
- **Por qué nadie se enteró:** las sondas de salud solo revisan `/healthz` y los tests no cubren los pedidos. Eso ya es una recomendación de prevención.
- **Plan de mitigación:** rollback a la revisión 2, con los comandos exactos y validado contra políticas de despliegue seguro. Además advirtió que la revisión 1 también falla, y que no conviene usar el script de despliegue porque cambiaría el balanceador.

### El beneficio, dicho fácil
> "Revisar logs, buscar qué cambió, leer el código y decidir el rollback normalmente le toma horas a un ingeniero. El agente lo entregó en **4,5 minutos**, con evidencia de cada paso. Y no se quedó en el *qué*: encontró *quién*, *cuándo* y *por qué no lo detectamos*."

---

## D2: Batch Java legado (15 min)

### El escenario, en una frase
"Un job Java que corre cada 5 minutos en un servidor EC2 empieza a fallar. Nadie tocó el código."

### Qué hacer
1. Mostrar en CloudWatch el log group `/demo/legacy-batch` con el `FileNotFoundException`, y la alarma `legacy-batch-job-failed` en ALARM.
2. Abrir la investigación: **"Batch job en /demo/legacy-batch fallando en instancia i-059781bcae870eedd"**.

### Qué encontró el agente (resultado real)
- **Síntoma:** el job falla en **todas** las ejecuciones desde hace ~4 días, y **la alarma no tenía ninguna acción configurada**. "Nadie se enteró en 4 días."
- **Causa:** la ruta de entrada cambió de `/opt/batch/data` a `/opt/batch/inbound`, y esa carpeta nunca se crea en el servidor. Lo comprobó comparando la última ejecución buena con las fallidas, y leyendo el *user data* de la instancia.
- **Origen:** dedujo que el servidor descarga la configuración desde la rama `main` de GitHub, y apuntó al cambio en `batch.properties`.
- **Transparencia:** dejó escrito lo que **no** verificó. No entró al servidor a leer el archivo, para no modificarlo.
- **Plan:** revertir el commit de configuración (opción permanente), o fijar el servidor a la última versión buena (opción rápida).
- **Tiempo:** 5,2 minutos.

### El beneficio, dicho fácil
> "En sistemas legados el problema casi nunca es el código: es una configuración, una ruta, una credencial. El agente conecta el error del log con el cambio de configuración, aunque el job no tenga monitoreo moderno. Solo necesitó los logs en CloudWatch."

**Nota para quien presenta:** esta investigación se ejecutó antes de conectar GitHub, por eso el origen quedó como *hipótesis*. Si la relanzas antes de la sesión, debería confirmar el commit exacto ("config(batch): move input to inbound directory").

---

## D3: Release testing, "¿va a funcionar después del cambio?" (15 min)

### El escenario, en una frase
"Un desarrollador hace un refactor para *simplificar* el código de cupones. **Los tests unitarios pasan.** ¿Lo dejamos pasar a producción?"

### Qué hacer
1. Mostrar el **PR #3** en GitHub: el cambio parece inocente y todo el CI está en verde.
2. Explicar el flujo: al desplegar en staging, GitHub Actions llama al agente con un webhook, y el agente **prueba la app como lo haría un usuario y como lo haría otro sistema**.
3. Abrir los resultados en Release Manager de `Demo-Agent`.

### Qué encontró el agente (resultado real)
- **Prueba de UI** (navegador real): 14 casos, **2 fallidos**. El cupón expirado `BLACKFRIDAY20` aplica 20% de descuento: USD 25,88 regalados en un carrito de USD 129,40. Severidad **alta**, con capturas de pantalla.
- **Prueba de API:** 18 escenarios, **3 fallidos**. El mismo defecto aparece en `/api/cart/price` y en `/api/orders`.
- **Tiempo:** unos 6 minutos (UI) y 7 minutos (API), en paralelo.
- El agente **escribió solo los casos de prueba**, a partir del cambio, del contrato de la API y de una instrucción en lenguaje natural. Nadie mantuvo una suite de regresión.

### El beneficio, dicho fácil
> "Los tests unitarios dijeron 'todo bien'. El agente dijo 'esto le va a costar plata cada vez que alguien use un cupón vencido'. Eso se detectó **antes** de producción, sin escribir un solo test a mano. Es la respuesta a '¿cómo sé si mi app va a funcionar después de un ajuste?'."

---

## Integración con GitHub (2 min, entre D1 y D3)

Lo que el cliente ya vio sin darse cuenta:
- **Investigación:** el agente lee el código y el historial de commits para llegar a la línea y al cambio responsable (D1, D2).
- **CI/CD:** una GitHub Action de AWS (`aws-actions/devops-agent-qa`) dispara el release testing después de cada despliegue en staging (D3).
- **Por API:** la investigación de D1 se creó con una llamada a la API (`create-backlog-task`). "Es la misma llamada que haría su scheduler, su sistema de tickets o una alarma."

---

## DevOps Agent y Dynatrace (5 min)

*Esta tabla compara el foco de cada producto, no es una auditoría de funcionalidades. Dynatrace evoluciona rápido: valida con el cliente qué tiene contratado.*

**Mensaje clave:** *no compiten, se complementan.* Dynatrace tiene una integración nativa en dos sentidos con DevOps Agent ([documentación de AWS](https://docs.aws.amazon.com/devopsagent/latest/userguide/connecting-telemetry-sources-connecting-dynatrace.html)).

| | Dynatrace (Davis AI) | AWS DevOps Agent |
|---|---|---|
| **Su fuerte** | Observabilidad profunda: instrumentación automática, trazas, análisis causal sobre su topología | Investigación de punta a punta sobre AWS: infraestructura, despliegues, auditoría y código |
| **Requiere** | Instalar OneAgent u Operator en los servidores | Nada en los servidores. Usa las APIs de AWS y lo que ya hay en CloudWatch |
| **Ve el código y los commits** | No es su foco principal | Sí: lee el repositorio y relaciona el fallo con el cambio |
| **Ve quién cambió qué en AWS** | Con integraciones | Sí, de forma nativa: CloudTrail y auditoría de EKS (en D1 identificó al usuario que desplegó) |
| **Antes de producción** | Enfocado en producción | **Release testing**: prueba los cambios en staging (D3) |
| **Plan de mitigación** | Workflows de remediación | Plan paso a paso, validado contra políticas de despliegue seguro |

**Cómo funcionan juntos:** un problema detectado en Dynatrace dispara una investigación en DevOps Agent. El agente consulta la telemetría de Dynatrace y publica la causa raíz y el plan **dentro de Dynatrace**. El equipo no cambia de herramienta.

**Qué NO decir:** que DevOps Agent "reemplaza" a Dynatrace, o que Dynatrace no tiene IA. Dynatrace tiene análisis causal maduro y su propio agente SRE. Si el cliente ya paga Dynatrace, el argumento es *sumar* el contexto de AWS, del código y del release testing.

---

## Cierre (3 min)

> "Vieron tres cosas: un error de código que el agente llevó hasta la línea y el commit; un batch legado que llevaba 4 días fallando sin que nadie se enterara; y un cambio que pasaba todos los tests y que el agente detuvo antes de producción. Todo en español, con evidencia, y sin instalar nada en sus servidores."

**Siguiente paso propuesto:** elegir **un caso real** (un job batch o una app que les dé problemas), conectarlo a un Agent Space en una cuenta de pruebas, y medir el tiempo de diagnóstico antes y después. Pedir el contacto técnico que lo implementaría.

---

## Preguntas probables

| Pregunta | Respuesta |
|---|---|
| ¿Puede romper algo? | Investiga con permisos de solo lectura. El plan de mitigación lo ejecuta una persona. El release testing sí hace escrituras, por eso se apunta a staging. |
| ¿Funciona con servidores on-premises? | Investiga lo que llega a sus fuentes: CloudWatch, Dynatrace, Datadog, Splunk o un servidor MCP propio. Hay que validarlo con su caso. |
| ¿Funciona con Azure DevOps o GitLab? | GitHub y GitLab están documentados para release management. Material de AWS menciona Azure DevOps como integración de CI/CD, pero hay que confirmar el alcance antes de prometerlo. |
| ¿Busca vulnerabilidades? | No. Para eso existe AWS Security Agent. El release testing busca regresiones funcionales. |
| ¿Qué tan confiable es? | Muestra evidencia de cada hallazgo y declara lo que no verificó (D2). No es determinista: conviene validar sus conclusiones, como con cualquier ingeniero nuevo. |
| ¿Está disponible en GA? | La investigación de incidentes sí. Release management (D3) está en *preview* en us-east-1. |

---

## Checklist antes de la sesión
- [ ] Relanzar la investigación de D2, ya con GitHub conectado, para que confirme el commit.
- [ ] Revisar en la web app que las investigaciones y los release tests se ven bien (capturas de respaldo).
- [ ] Decidir qué estado dejar desplegado. Para empezar D1 en vivo: `./demo/deploy.sh cd491e91fedada7fa47f8b0bf584b9df6b8f1b79`.
- [ ] Verificar el login de SSO (`aws sso login --profile aidlc-workshop`).
- [ ] Revisar en el reporte de API de D3 la frase "validación duplicada por endpoint": no es correcta, porque ambos endpoints usan `price()`. No la presentes como hallazgo.
