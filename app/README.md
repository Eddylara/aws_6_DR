# API de Personas

Aplicación simple en Flask para gestionar personas mediante una API REST.

## Base

- Método de verificación: `GET /health`
- Endpoint principal: `GET /api/personas`

## Campos de la persona

La API usa estos campos en JSON:

- `id`: entero opcional al crear
- `nombre`: texto obligatorio
- `edad`: entero obligatorio

Ejemplo:

```json
{
  "nombre": "Juan",
  "edad": 30
}
```

## Endpoints

### `GET /api/personas`
Devuelve todas las personas guardadas.

Respuesta ejemplo:

```json
[
  {
    "id": 1,
    "nombre": "Juan",
    "edad": 30
  }
]
```

### `POST /api/personas`
Crea una persona nueva.

Body JSON:

```json
{
  "nombre": "Ana",
  "edad": 25
}
```

También puede recibir `id` si se desea enviar uno manualmente:

```json
{
  "id": 10,
  "nombre": "Ana",
  "edad": 25
}
```

Respuesta ejemplo:

```json
{
  "id": 10,
  "nombre": "Ana",
  "edad": 25
}
```

### `PUT /api/personas/{id}`
Actualiza una persona existente.

Ejemplo:

```bash
PUT /api/personas/10
```

Body JSON:

```json
{
  "nombre": "Ana Maria",
  "edad": 26
}
```

### `DELETE /api/personas/{id}`
Elimina una persona por ID.

Ejemplo:

```bash
DELETE /api/personas/10
```

Respuesta ejemplo:

```json
{
  "deleted": 10
}
```

## Ejemplos con curl

Crear:

```bash
curl -X POST http://ALB/api/personas \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Juan","edad":30}'
```

Listar:

```bash
curl http://ALB/api/personas
```

Actualizar:

```bash
curl -X PUT http://ALB/api/personas/1 \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Juan Perez","edad":31}'
```

Eliminar:

```bash
curl -X DELETE http://ALB/api/personas/1
```

## Respuestas de error

- `400`: faltan campos obligatorios
- `404`: persona no encontrada

## Nota

La ruta `/` devuelve un mensaje JSON simple para evitar depender de HTML.
