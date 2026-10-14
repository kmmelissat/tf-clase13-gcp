# Clase 13: Terraform II, estado e idempotencia (Google Cloud)

Práctica con el provider `hashicorp/google` 8.1.0 en el proyecto `delta-trees-509819-p7`: una service account (`tf-state-runtime`) y un servicio de Cloud Run (`tf-state-api`) que la usa como identidad de ejecución.

Archivos: `main.tf`, `variables.tf`, `terraform.tfvars.example` (plantilla), `.gitignore`. `terraform.tfvars` y el state no se versionan. `.terraform.lock.hcl` sí.

## 6.2 Antes de ejecutar

- **Direcciones de recursos:** `google_service_account.runtime` y `google_cloud_run_v2_service.api`.
- **Referencia que crea la dependencia:** `service_account = google_service_account.runtime.email`.
- **Qué debe existir antes:** la service account, porque Cloud Run necesita su email.
- **Valores conocidos solo tras el apply:** `id`, `unique_id` y `email` confirmado de la cuenta, y en Cloud Run `uid`, `uri`, `etag`, `conditions` y `latest_ready_revision`.
- **Origen del Project ID y la región:** `terraform.tfvars`, declaradas en `variables.tf` (`var.project_id` y `var.region`).

## Resultados de la práctica

| Paso | Resultado |
|---|---|
| plan inicial | `2 to add, 0 to change, 0 to destroy`, con valores `(known after apply)`. |
| apply | `2 added`. Verificado con `gcloud iam service-accounts describe` y `gcloud run services describe`. |
| plan sin cambios | "No changes". |
| `description` agregado | `update in-place`: `0 to add, 1 to change, 0 to destroy`. |
| plan final | "No changes". |

## Puntos de control

**PC1. ¿Qué debe mostrar `state list` antes del primer apply?** Nada: `No state file was found`. El plan describe acciones futuras y no crea asociaciones en el state.

**PC2. Clasificación de atributos.**

| Origen | Atributos |
|---|---|
| Definidos en `main.tf` | `account_id`, `display_name`, `name = "tf-state-api"`, `deletion_protection`, `image` |
| De `terraform.tfvars` | `project` (`var.project_id`) y `location` (`var.region`) |
| Por referencia a otro recurso | `template.service_account`, tomado de `google_service_account.runtime.email` |
| Calculados por el provider | `id`, `unique_id`, `name` de la cuenta; en Cloud Run `uid`, `uri`, `urls`, `etag`, `generation`, `conditions`, `latest_ready_revision`, `create_time`, `creator` |

**PC3. Identificadores.**
- `google_cloud_run_v2_service.api` identifica al recurso dentro de la configuración y el state de Terraform.
- `tf-state-api` identifica al servicio en Google Cloud.
- Terraform conserva información adicional (`id`, `uid`, `uri`, atributos calculados) porque solo existe después de crear el objeto y es lo que le permite encontrarlo, compararlo y modificarlo después.

**PC4. ¿Por qué no basta `terraform.tfstate`?** El state es un registro de lo que Terraform sabía la última vez. Para concluir que no hay cambios debe consultar también la infraestructura real (refresh) y compararla con la configuración. Sin eso no detectaría cambios hechos fuera de Terraform.

**Pregunta de 6.8.** Cambia `google_cloud_run_v2_service.api`. Se actualiza el recurso existente. La evidencia es `~ update in-place`, la línea `+ description` y el resumen `0 to add, 1 to change, 0 to destroy`, sin `forces replacement`.

## 7. Actividades de análisis

**Actividad 1. Asociación entre configuración y objeto remoto.** Terraform asocia una dirección con un objeto remoto mediante el state, que guarda el ID del objeto creado o importado. Que exista una cuenta con el mismo nombre no crea esa asociación. Si no está en el state, Terraform planearía crearla, y el apply fallaría porque ya existe, o duplicaría el recurso. Para administrar un objeto existente hay que importarlo.

**Actividad 2. Lectura del state.** Con `terraform.tfstate` sin `main.tf` siguen disponibles las direcciones, los IDs y los atributos que Terraform conoció. Pero el state describe lo que existe, no lo que se quiere. Sin configuración no hay estado deseado, y Terraform interpretaría que esos recursos ya no se declaran y propondría destruirlos.

**Actividad 3. Plan sin cambios.** El plan no hizo nada porque Terraform comparó tres fuentes: la configuración (estado deseado), el state (lo que registró) y la infraestructura real (consultada al provider en el refresh). No encontró diferencias, así que el sistema ya convergió al estado deseado. No repite el apply anterior. Es idempotente: ejecutarlo de nuevo con las mismas entradas no cambia nada.

**Actividad 4. State desactualizado.** Un plan normal actualiza primero la información de los objetos remotos y la compara con la configuración, así que detecta que el objeto cambió fuera de Terraform. Con `-refresh=false` omite esa consulta y trabaja con lo que dice el state, que está viejo. El plan puede decir "No changes" aunque la realidad ya difiere, o proponer acciones sobre datos obsoletos, y el apply puede sobrescribir cambios o fallar.

**Actividad 5. Estado sensible.**
- **Seguridad:** el state puede contener valores sensibles (contraseñas, tokens, claves) en texto plano, y quedarían en el historial de Git para todo el que tenga acceso, aun si luego se borran.
- **Coordinación:** Git no bloquea. Dos personas pueden aplicar a la vez con copias distintas del state y corromper la asociación con los objetos reales.
- **Conflictos:** el state es un JSON con serial y metadatos generados por Terraform. Los merges o rebases pueden romperlo, y no se puede editar a mano de forma segura.
- **Desactualización:** nadie garantiza que la copia del repositorio sea la última, y esa copia vieja produce planes incorrectos.
