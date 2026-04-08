---
name: api-design
description: REST API design patterns and conventions
tags: [api, design, rest]
---

# API Design Patterns

Guidelines for designing REST APIs.

## Resource-Oriented Design

Design around resources, not actions.

### Good
- `GET /users/123` — Get a user
- `POST /users` — Create a user
- `PUT /users/123` — Update a user
- `DELETE /users/123` — Delete a user

### Avoid
- `GET /getUser` — Action-oriented
- `POST /createNewUser` — Redundant with HTTP method

## HTTP Methods

| Method | Purpose | Idempotent |
|--------|---------|-----------|
| GET | Retrieve | Yes |
| POST | Create | No |
| PUT | Full update | Yes |
| PATCH | Partial update | No |
| DELETE | Delete | Yes |

## Status Codes

### 2xx Success
- `200 OK` — Request succeeded
- `201 Created` — Resource created (include Location header)
- `204 No Content` — Success, no response body

### 4xx Client Error
- `400 Bad Request` — Invalid input
- `401 Unauthorized` — Authentication required
- `403 Forbidden` — Authenticated, not allowed
- `404 Not Found` — Resource doesn't exist
- `422 Unprocessable Entity` — Valid format, semantic error

### 5xx Server Error
- `500 Internal Server Error` — Unexpected error
- `503 Service Unavailable` — Temporarily down

## Error Responses

Consistent error format:

```json
{
  "error": {
    "code": "INVALID_INPUT",
    "message": "User email is required",
    "details": {
      "field": "email"
    }
  }
}
```

## Request/Response Bodies

### JSON Structure
- Use camelCase for fields
- Flat structure (max 2-3 nesting levels)
- Avoid redundant wrappers

```json
{
  "userId": 123,
  "name": "Alice",
  "email": "alice@example.com",
  "createdAt": "2026-01-15T10:30:00Z"
}
```

### Timestamps
- Use ISO 8601: `2026-01-15T10:30:00Z`
- Timezone-aware (UTC)

## Pagination

```
GET /users?page=1&limit=20
```

Response:

```json
{
  "data": [{...}, {...}],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 150,
    "hasMore": true
  }
}
```

## Filtering, Sorting

### Filtering
```
GET /users?role=admin&status=active
```

### Sorting
```
GET /posts?sort=createdAt:desc,title:asc
```

## Versioning

### URL Path (Recommended)
```
GET /v1/users
GET /v2/users
```

### Header
```
Accept: application/vnd.myapi.v1+json
```

Announce 12 months before deprecating old versions.

## Authentication

### Bearer Token
```
Authorization: Bearer <token>
```

### API Key
```
X-API-Key: your-key-here
```

## Rate Limiting

Include in response headers:

```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 500
X-RateLimit-Reset: 1234567890
```

## Common Patterns

### Nested Resources
```
GET /organizations/org1/teams/team1/members
```

Or flatten with query params:
```
GET /members?organizationId=org1&teamId=team1
```

### Batch Operations
```
POST /users/batch
{
  "operations": [
    {"op": "create", "data": {...}},
    {"op": "update", "id": "123", "data": {...}}
  ]
}
```
