# CONVENTIONS

> Stable conventions. Changes require ADR + PR review.
> Deterministic checks are enforced by pre-commit + CI, not by the agent.

## Runtime
- <language + version>
- Dep manager: <e.g. uv / pnpm>. Lockfile committed.
- Install: `make setup`. Run: `make dev`.

## Layout (flat, layered by concern)

```
<source-root>/
  <domain>/
    routes/      Thin HTTP layer; parse, call service, return response.
    services/    Business logic; async; dependency-injected.
    repositories/  SQL / ORM boundary; never imported from routes.
    schemas/     Request/response types (Pydantic v2 / Zod).
    models/      DB models.
    exceptions/  Domain exceptions.
```

Router → Service → Repository. No business logic in routers. No DB access
in services.

## Async
- Async-first on supported stacks.
- Sync SDKs wrap with `anyio.to_thread.run_sync` (Python) / worker threads (Node).
- Never block the event loop inside `async def`.
- Fan out independent I/O with `asyncio.gather(..., return_exceptions=True)`.

## Error handling
- Raise domain exceptions from `<domain>/exceptions.py`.
- Single exception handler at app root translates to HTTP.
- Never bare `except Exception:` without re-raise or structured log.
- 4xx = caller; 5xx = ours.

## Logging
- JSON to stdout. Structured logging library (structlog / pino).
- Never log secrets, tokens, PII.
- Bind `request_id`, `trace_id`, `user_id` at middleware.
- Levels: debug (local only), info (business events), warning (degraded),
  error (unexpected).

## Testing
- Test framework: pytest / vitest / etc. per stack.
- Coverage: see `VIBE.yaml` `quality_gates.tests.coverage.minimum_percentage`.
- No snapshot tests. No test-against-test-double-only suites.
- Test structure mirrors source: `tests/routes/`, `tests/services/`.

## Dependency injection
- Shared deps in `<source>/deps/`, registered once in app factory.
- No global mutable state.

## Migrations
- One revision per PR, reversible.
- Never edit a merged migration.

## API contracts
- Every route: summary, response model, error responses.
- Status codes on decorators; no raw HTTPException with numeric literals.
- `/api/health`, `/api/docs`, `/api/openapi` — mandatory on every API service
  (agentic-skeleton contract).

## What NOT to put in prompts (the linter's job)

- Formatting rules — pre-commit + `make fix`
- Import ordering — linter
- Type nitpicks — `make typecheck`
- Terraform formatting — `terraform fmt -recursive`

## Stack-specific additions

<!-- If you ran bootstrap-greenfield.sh with a --stack flag, the lang-* skill
     appended its conventions here. -->
