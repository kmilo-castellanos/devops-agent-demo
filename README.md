# Demo: AWS DevOps Agent, release testing sobre EKS

App de ejemplo ("Demo Shop", Node sin dependencias) desplegada en EKS con un endpoint público. Un PR con una regresión sutil pasa los tests unitarios, pero el release testing de DevOps Agent la detecta.

```
PR ─► GitHub Actions ─► unit tests ─► build ─► GHCR
                                                │  ./demo/deploy.sh <sha>  (desde tu máquina)
                                                ▼
                                   EKS cluster-test (NLB público)
                                                │  /version == sha del commit
        Check Run (pass/fail) ◄── DevOps Agent ◄┘  webhook (target-url)
```

> Release management está en **preview** y solo en **us-east-1**. El agente ejecuta escrituras reales (POST/DELETE) contra la app. Aquí el estado es en memoria, así que es seguro. El endpoint es público y sin autenticación: destruye todo al terminar.

## Contenido

| Ruta | Para qué |
|---|---|
| `app/` | App, tests unitarios (solo camino feliz), `openapi.yaml` con el comportamiento esperado de los cupones |
| `k8s/shop.yaml` | Namespace, Deployment y Service `LoadBalancer` (NLB público, EKS Auto Mode) |
| `infra/` | Opcional. `eksctl` y OIDC de GitHub, solo si tienes permisos de IAM (no se usan en esta variante) |
| `demo/deploy.sh` | Despliega en EKS la imagen de GHCR de un commit |
| `.github/workflows/deploy-and-test.yml` | Tests → build a GHCR → espera el despliegue → release testing (UI y API) |
| `demo/plant-regression.sh` | Crea la rama con la regresión y la sube |
| `demo/break-deployment.sh` | Opcional: rompe el deployment para la investigación |

## Preparación

Requisitos locales: `aws` (perfil con acceso a `cluster-test`), `kubectl`, `git`. Docker no hace falta.

**1. Repo en GitHub.** `kmilo-castellanos/devops-agent-demo`, con este contenido en `main`.

**2. Agent Space** (consola de AWS DevOps Agent, us-east-1)
1. Crea el Agent Space.
2. *Capability Providers* → añade **GitHub** (instala la GitHub App en tu cuenta).
3. *Pipeline Sources* → añade el repositorio.
4. *Settings → Webhooks* → crea un webhook y copia URL y secret.
5. Para el bloque de investigación: asocia la cuenta AWS del cluster y da al rol del agente acceso al cluster con un EKS access entry.
6. Conecta el repo también como código fuente (la indexación tarda 1 a 2 horas).

**3. GitHub Secrets** (*Settings → Secrets and variables → Actions*): `DEVOPS_AGENT_WEBHOOK_URL`, `DEVOPS_AGENT_WEBHOOK_SECRET`.

**4. Primer push a `main`.** Actions construye `ghcr.io/kmilo-castellanos/devops-agent-demo:<sha>`. Después del primer build, abre *Packages → devops-agent-demo → Package settings* y cambia la visibilidad a **Public** para que el cluster pueda descargar la imagen sin credenciales (solo contiene código de demo).

**5. Primer despliegue**
```bash
export AWS_PROFILE=aidlc-workshop
./demo/deploy.sh            # despliega HEAD
```
Imprime la URL pública. Guárdala como **variable** de GitHub (no secret) llamada `STAGING_URL`, con el formato `http://<host>` sin barra final. Vuelve a lanzar el workflow (*Actions → Run workflow*): `release-test` debe terminar en verde.

**6. Ensayo completo** de la sección siguiente.

## Guion (~30 min)

### A. Línea base (3 min)
Muestra la app en la URL pública. Prueba `SAVE10`. Prueba `BLACKFRIDAY20` y comprueba que da error "Coupon has expired". Abre el check de release testing en verde del commit a `main`.

### B. Introducir la regresión (5 min)
```bash
./demo/plant-regression.sh
```
Abre el PR con el enlace que imprime. Cuando Actions termine el build (job `build-image`), despliega la rama:
```bash
./demo/deploy.sh $(git rev-parse HEAD)
```
El job `wait-for-deploy` detecta que `/version` ya devuelve ese commit y lanza el release testing. El cambio parece un refactor de `applyCoupon` ("simplify coupon validation") y elimina la comprobación de expiración. Resalta que el job `unit-tests` **pasa**, porque los tests no cubren cupones expirados.

### C. Release testing (10 a 15 min)
En el PR, `release-test` lanza dos agentes en paralelo (UI y API). Mientras corren, abre la Operator App del Agent Space y muestra el plan de pruebas generado y la ejecución. Resultado esperado: el check **falla** con la reproducción: `BLACKFRIDAY20` devuelve 200 con 20% de descuento (o el checkout se completa) en lugar de 400 `coupon_expired`. Muestra los screenshots de UI, los pasos de reproducción y el fix recomendado.

### D. Prueba manual desde el chat (5 min)
En el chat de DevOps Agent:
- `List my test profiles`
- `Run release testing on <URL> and verify that expired coupons are rejected in the checkout`

### E. Opcional, desde Kiro IDE
Con el Kiro power de DevOps Agent instalado, pide al agente que valide el flujo de cupones y que arregle lo que encuentre. Desde el IDE no se prueba un PR directamente: hay que usar una URL desplegada.

### F. Opcional, bloque de investigación en EKS (GA)
```bash
./demo/break-deployment.sh
```
En el chat: `Investigate why deployment shop in namespace shop is not ready`. El agente recorre topología, eventos de Kubernetes y el despliegue reciente, y propone una mitigación. Restaura con `kubectl -n shop rollout undo deployment/shop`.

### Cerrar la demo
Haz merge del fix o cierra el PR. Para que `main` vuelva a verde, el siguiente push a `main` redespliega la versión correcta.

## Notas y riesgos

- **No determinismo.** El agente puede variar el recorrido entre ejecuciones. Ensaya y guarda capturas de un run exitoso como respaldo.
- **Un único staging.** El PR se despliega sobre el mismo entorno que `main`, a mano con `deploy.sh`. Con un rol IAM de OIDC (ver `infra/`) se podría automatizar. Es válido para la demo, no para un equipo real.
- **Modo guest.** El release testing sin test profile no soporta login. Si el cliente pregunta por apps autenticadas, enseña la opción de *test profile* con credenciales y TOTP/email 2FA.
- **Regresión basada en fecha.** `BLACKFRIDAY20` expira en 2020, así que el comportamiento es estable.
- **Nombre de la action.** Es `aws-actions/devops-agent-qa@v1` (el repo `devops-agent-release-testing` no existe). La documentación de AWS se contradice en este punto.
- **NLB en el Service.** Usa `loadBalancerClass: eks.amazonaws.com/nlb`, válido para clusters con EKS Auto Mode (como `cluster-test`). En un cluster sin Auto Mode hay que instalar el AWS Load Balancer Controller.

## Limpieza

```bash
kubectl delete ns shop   # elimina el NLB y la app; el cluster no es de esta demo, no se borra
```
Elimina también el Agent Space, el webhook y, si quieres, el paquete de GHCR.
