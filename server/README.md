# RiffShelf backend

This independent FastAPI service is the starting point for search and metadata APIs. `GET /health` returns `{"status":"ok"}` when the process responds; it is not a check of external providers. The `/api/v1` router is reserved for future search and metadata routes. No provider endpoints or tab storage are included.

## Install, run, and test on macOS or Linux

Install Python 3.14 (including its `venv` module; on Ubuntu install the matching Python venv package if needed). From the repository root:

```sh
cd server
python3.14 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m pytest
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

These commands use a project-local virtual environment and pinned direct and transitive dependencies. Port 8000 is only a local development example; choose another if occupied. In another terminal, verify:

```sh
curl -fsS http://127.0.0.1:8000/health
curl -fsS http://127.0.0.1:8000/docs
curl -fsS http://127.0.0.1:8000/openapi.json
```

Open `http://127.0.0.1:8000/docs` in a browser for the interactive Swagger UI (its assets require network access). Stop the server with Ctrl-C and leave the virtual environment with `deactivate`.

## Configuration

`RIFFSHELF_DOCS_ENABLED` defaults to `true` for local development. Set it to `false` before starting the service to disable `/docs` and `/openapi.json`. Values are case-insensitive `true` or `false`; invalid values fail startup. For example:

```sh
export RIFFSHELF_DOCS_ENABLED=false
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

No credentials are required. The host and port are Uvicorn command-line options, not assumed deployment settings. Do not commit secrets or local environment files.

## Before any SkyNet deployment

The authoritative `SkyNet_Server_Context.md` in the ChatGPT Library was not available to this implementation session. Read it and confirm it is current before making deployment decisions. On the Ubuntu server, first verify:

- The intended host, access method, operator permissions, and existing services and policies.
- A free, approved listening address and port, using the server's existing network and firewall configuration; check current listeners before choosing one.
- An approved deployment directory, service account, Python 3.14 and venv availability, disk space, and dependency installation method.
- Existing reverse proxy, TLS, DNS, firewall, service manager, logging, restart, update, and rollback conventions before selecting any configuration.
- Whether API documentation should be disabled and how future secrets and provider access will be handled.

No SkyNet installation or deployment is performed by these instructions.
