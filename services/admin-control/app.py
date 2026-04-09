from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import docker
from docker.errors import DockerException, NotFound
from fastapi import FastAPI, Form, HTTPException, Request, status
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, Field
from starlette.middleware.sessions import SessionMiddleware

APP_DIR = Path(__file__).resolve().parent
STATE_DIR = Path(os.getenv("ADMIN_STATE_DIR", "/data/admin-control"))
REGISTRY_FILE = STATE_DIR / "service-registry.json"
STATE_FILE = STATE_DIR / "service-state.json"
SEED_FILE = APP_DIR / "registry.seed.json"
SESSION_SECRET = os.getenv("ADMIN_SESSION_SECRET", "")
ADMIN_USERNAME = os.getenv("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD_HASH = os.getenv("ADMIN_PASSWORD_HASH", "")
ADMIN_API_TOKEN = os.getenv("ADMIN_API_TOKEN", "")
SECURE_COOKIES = str(os.getenv("ADMIN_SECURE_COOKIES", "1")).strip().lower() in {"1", "true", "yes", "on"}
PROTECTED_KEYS = {"admin-control", "traefik"}
LOGIN_WINDOW_SECONDS = 15 * 60
LOGIN_MAX_ATTEMPTS = 5

app = FastAPI(title="admin-control")
app.add_middleware(
    SessionMiddleware,
    secret_key=SESSION_SECRET or "replace-me-in-env",
    same_site="lax",
    https_only=SECURE_COOKIES,
    session_cookie="admin_control_session",
    max_age=60 * 60 * 12,
)
app.mount("/static", StaticFiles(directory=str(APP_DIR / "static")), name="static")
templates = Jinja2Templates(directory=str(APP_DIR / "templates"))

_login_attempts: dict[str, list[float]] = defaultdict(list)


class ManagedServiceRegistration(BaseModel):
    key: str = Field(min_length=1, max_length=64)
    display_name: str = Field(min_length=1, max_length=120)
    container_name: str = Field(min_length=1, max_length=128)
    description: str = Field(default="", max_length=280)
    exposure: str = Field(default="custom", max_length=64)
    public_hosts: list[str] = Field(default_factory=list)
    default_auto_start: bool = True
    protected: bool = False


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_data_files() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    if not REGISTRY_FILE.exists():
        REGISTRY_FILE.write_text(SEED_FILE.read_text(), encoding="utf-8")
    else:
        raw_registry = json.loads(REGISTRY_FILE.read_text(encoding="utf-8"))
        services = raw_registry.get("services", [])
        filtered = [service for service in services if service.get("key") != "cloudflared"]
        if len(filtered) != len(services):
            REGISTRY_FILE.write_text(
                json.dumps({"version": 1, "services": filtered}, indent=2) + "\n",
                encoding="utf-8",
            )
    if not STATE_FILE.exists():
        STATE_FILE.write_text(json.dumps({"version": 1, "services": {}}, indent=2) + "\n", encoding="utf-8")


def load_registry() -> dict[str, dict[str, Any]]:
    ensure_data_files()
    raw = json.loads(REGISTRY_FILE.read_text(encoding="utf-8"))
    services = raw.get("services", [])
    return {service["key"]: service for service in services if isinstance(service, dict) and service.get("key")}


def save_registry(registry: dict[str, dict[str, Any]]) -> None:
    ensure_data_files()
    payload = {
        "version": 1,
        "services": [registry[key] for key in sorted(registry)],
    }
    REGISTRY_FILE.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def load_state() -> dict[str, Any]:
    ensure_data_files()
    raw = json.loads(STATE_FILE.read_text(encoding="utf-8"))
    raw.setdefault("version", 1)
    raw.setdefault("services", {})
    return raw


def save_state(state: dict[str, Any]) -> None:
    ensure_data_files()
    STATE_FILE.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


def get_docker_client():
    try:
        return docker.from_env()
    except DockerException:
        return None


def parse_public_hosts(labels: dict[str, str]) -> list[str]:
    hosts: set[str] = set()
    for key, value in labels.items():
        if key.startswith("traefik.http.routers.") and key.endswith(".rule"):
            parts = value.split("Host(")
            for part in parts[1:]:
                host_blob = part.split(")", 1)[0]
                for candidate in host_blob.split(","):
                    cleaned = candidate.strip().strip("`'\" ")
                    if cleaned:
                        hosts.add(cleaned)
    return sorted(hosts)


def is_truthy(value: str | None) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def normalize_key(value: str) -> str:
    allowed = []
    for char in value.strip().lower():
        if char.isalnum() or char in {"-", "_"}:
            allowed.append(char)
        elif char in {" ", "."}:
            allowed.append("-")
    normalized = "".join(allowed).strip("-_")
    if not normalized:
        raise ValueError("Service key must include letters or numbers.")
    return normalized


def get_container_map() -> dict[str, Any]:
    client = get_docker_client()
    if client is None:
        return {}
    try:
        containers = client.containers.list(all=True)
    except DockerException:
        return {}
    return {container.name: container for container in containers}


def merge_service_record(
    base: dict[str, Any] | None,
    override: dict[str, Any] | None,
) -> dict[str, Any]:
    merged: dict[str, Any] = {}
    for source in (base or {}, override or {}):
        for key, value in source.items():
            if value in (None, "", []):
                continue
            merged[key] = value
    merged.setdefault("public_hosts", [])
    merged["public_hosts"] = sorted(set(merged.get("public_hosts", [])))
    merged.setdefault("protected", False)
    merged.setdefault("default_auto_start", True)
    return merged


def build_services() -> list[dict[str, Any]]:
    registry = load_registry()
    state = load_state()
    containers = get_container_map()
    services: dict[str, dict[str, Any]] = {}

    for key, entry in registry.items():
        service = dict(entry)
        service["key"] = key
        services[key] = service

    for container_name, container in containers.items():
        labels = container.labels or {}
        managed = is_truthy(labels.get("homelab.admin.managed"))
        registry_key = next(
            (
                key
                for key, entry in registry.items()
                if entry.get("container_name") == container_name
            ),
            None,
        )
        if not managed and registry_key is None:
            continue

        key = labels.get("homelab.admin.key") or registry_key or container_name
        discovered = {
            "key": key,
            "display_name": labels.get("homelab.admin.name") or key.replace("-", " ").title(),
            "container_name": container_name,
            "description": labels.get("homelab.admin.description", ""),
            "exposure": labels.get("homelab.admin.exposure", "custom"),
            "public_hosts": parse_public_hosts(labels),
            "protected": is_truthy(labels.get("homelab.admin.protected")),
            "default_auto_start": not (
                labels.get("homelab.admin.default_auto_start", "").strip().lower() in {"0", "false", "no", "off"}
            ),
        }
        services[key] = merge_service_record(services.get(key), discovered)

    results: list[dict[str, Any]] = []
    for key, service in services.items():
        container_name = service.get("container_name")
        container = containers.get(container_name or "")
        status_value = "not-found"
        running = False
        if container is not None:
            status_value = container.status
            running = status_value == "running"

        service_state = state.get("services", {}).get(key, {})
        auto_start = service_state.get("auto_start", service.get("default_auto_start", True))
        protected = bool(service.get("protected")) or key in PROTECTED_KEYS

        results.append(
            {
                **service,
                "status": status_value,
                "running": running,
                "auto_start": auto_start,
                "protected": protected,
                "last_action": service_state.get("last_action"),
                "last_action_at": service_state.get("last_action_at"),
                "last_actor": service_state.get("last_actor"),
                "missing_container": container is None,
            }
        )

    return sorted(results, key=lambda item: (item.get("protected", False), item["display_name"].lower()))


def find_service(service_key: str) -> dict[str, Any]:
    for service in build_services():
        if service["key"] == service_key:
            return service
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Service not found")


def get_exact_container(container_name: str):
    client = get_docker_client()
    if client is None:
        raise HTTPException(status_code=503, detail="Docker daemon is unavailable")
    try:
        return client.containers.get(container_name)
    except NotFound as exc:
        raise HTTPException(status_code=404, detail=f"Container '{container_name}' not found") from exc
    except DockerException as exc:
        raise HTTPException(status_code=503, detail="Docker daemon is unavailable") from exc


def ensure_password_hash_present() -> None:
    if not ADMIN_PASSWORD_HASH:
        raise HTTPException(
            status_code=503,
            detail="ADMIN_PASSWORD_HASH is not configured. Generate one with scripts/hash_admin_password.py.",
        )


def verify_password(password: str, encoded: str) -> bool:
    if not encoded:
        return False
    try:
        algorithm, iterations, salt_b64, digest_b64 = encoded.split("$", 3)
    except ValueError:
        return False
    if algorithm != "pbkdf2_sha256":
        return False
    try:
        salt = base64.b64decode(salt_b64.encode("ascii"))
        expected = base64.b64decode(digest_b64.encode("ascii"))
    except Exception:
        return False
    derived = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, int(iterations))
    return hmac.compare_digest(derived, expected)


def get_client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def check_rate_limit(request: Request) -> None:
    ip = get_client_ip(request)
    now = time.time()
    attempts = [ts for ts in _login_attempts[ip] if now - ts < LOGIN_WINDOW_SECONDS]
    _login_attempts[ip] = attempts
    if len(attempts) >= LOGIN_MAX_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many login attempts. Try again later.")


def record_login_failure(request: Request) -> None:
    ip = get_client_ip(request)
    _login_attempts[ip].append(time.time())


def clear_login_failures(request: Request) -> None:
    ip = get_client_ip(request)
    _login_attempts.pop(ip, None)


def get_session_user(request: Request) -> str | None:
    return request.session.get("user")


def require_session_user(request: Request) -> str:
    user = get_session_user(request)
    if user != ADMIN_USERNAME:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Authentication required")
    return user


def get_request_actor(request: Request) -> str:
    auth_header = request.headers.get("authorization", "")
    if ADMIN_API_TOKEN and auth_header == f"Bearer {ADMIN_API_TOKEN}":
        return "api-token"
    return require_session_user(request)


def require_csrf(request: Request) -> None:
    form_token = request.headers.get("x-csrf-token")
    session_token = request.session.get("csrf_token")
    if not session_token or form_token != session_token:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Invalid CSRF token")


def update_service_state(service_key: str, *, auto_start: bool | None, action: str, actor: str) -> None:
    state = load_state()
    service_state = state.setdefault("services", {}).setdefault(service_key, {})
    if auto_start is not None:
        service_state["auto_start"] = auto_start
    service_state["last_action"] = action
    service_state["last_action_at"] = utc_now()
    service_state["last_actor"] = actor
    save_state(state)


def act_on_service(service_key: str, action: str, actor: str) -> dict[str, Any]:
    service = find_service(service_key)
    if service["protected"] and action in {"stop", "disable"}:
        raise HTTPException(status_code=403, detail="This service is protected from remote stop or disable actions.")

    container = get_exact_container(service["container_name"])

    if action == "start":
        container.start()
        update_service_state(service_key, auto_start=None, action=action, actor=actor)
    elif action == "stop":
        container.stop(timeout=20)
        update_service_state(service_key, auto_start=None, action=action, actor=actor)
    elif action == "enable":
        update_service_state(service_key, auto_start=True, action="enable-auto-start", actor=actor)
        if container.status != "running":
            container.start()
    elif action == "disable":
        update_service_state(service_key, auto_start=False, action="disable-auto-start", actor=actor)
        if container.status == "running":
            container.stop(timeout=20)
    else:
        raise HTTPException(status_code=400, detail="Unknown action")

    return find_service(service_key)


def upsert_registration(payload: ManagedServiceRegistration, actor: str) -> dict[str, Any]:
    registry = load_registry()
    try:
        key = normalize_key(payload.key)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    registry[key] = {
        "key": key,
        "display_name": payload.display_name.strip(),
        "container_name": payload.container_name.strip(),
        "description": payload.description.strip(),
        "exposure": payload.exposure.strip() or "custom",
        "public_hosts": sorted({host.strip() for host in payload.public_hosts if host.strip()}),
        "default_auto_start": payload.default_auto_start,
        "protected": payload.protected,
        "updated_at": utc_now(),
        "updated_by": actor,
    }
    save_registry(registry)
    return registry[key]


def csrf_token(request: Request) -> str:
    token = request.session.get("csrf_token")
    if not token:
        token = secrets.token_urlsafe(24)
        request.session["csrf_token"] = token
    return token


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/login")
def login_page(request: Request):
    if get_session_user(request) == ADMIN_USERNAME:
        return RedirectResponse(url="/", status_code=303)
    return templates.TemplateResponse(
        request,
        "login.html",
        {"error": request.query_params.get("error")},
    )


@app.post("/login")
async def login(
    request: Request,
    username: str = Form(...),
    password: str = Form(...),
):
    ensure_password_hash_present()
    check_rate_limit(request)
    if username != ADMIN_USERNAME or not verify_password(password, ADMIN_PASSWORD_HASH):
        record_login_failure(request)
        return RedirectResponse(url="/login?error=invalid", status_code=303)

    clear_login_failures(request)
    request.session.clear()
    request.session["user"] = ADMIN_USERNAME
    request.session["csrf_token"] = secrets.token_urlsafe(24)
    return RedirectResponse(url="/", status_code=303)


@app.post("/logout")
async def logout(request: Request):
    require_session_user(request)
    require_csrf(request)
    request.session.clear()
    return RedirectResponse(url="/login", status_code=303)


@app.get("/")
def dashboard(request: Request):
    user = get_session_user(request)
    if user != ADMIN_USERNAME:
        return RedirectResponse(url="/login", status_code=303)
    services = build_services()
    return templates.TemplateResponse(
        request,
        "dashboard.html",
        {
            "services": services,
            "csrf_token": csrf_token(request),
            "admin_username": user,
            "api_token_enabled": bool(ADMIN_API_TOKEN),
        },
    )


@app.post("/services/{service_key}/action/{action}")
async def service_action(request: Request, service_key: str, action: str):
    actor = require_session_user(request)
    form = await request.form()
    if form.get("csrf_token") != request.session.get("csrf_token"):
        raise HTTPException(status_code=403, detail="Invalid CSRF token")
    act_on_service(service_key, action, actor)
    return RedirectResponse(url="/", status_code=303)


@app.post("/services/register")
async def register_service(
    request: Request,
    key: str = Form(...),
    display_name: str = Form(...),
    container_name: str = Form(...),
    description: str = Form(""),
    exposure: str = Form("custom"),
    public_hosts: str = Form(""),
):
    actor = require_session_user(request)
    form = await request.form()
    if form.get("csrf_token") != request.session.get("csrf_token"):
        raise HTTPException(status_code=403, detail="Invalid CSRF token")

    payload = ManagedServiceRegistration(
        key=key,
        display_name=display_name,
        container_name=container_name,
        description=description,
        exposure=exposure,
        public_hosts=[host.strip() for host in public_hosts.split(",") if host.strip()],
    )
    upsert_registration(payload, actor)
    return RedirectResponse(url="/", status_code=303)


@app.get("/api/services")
def api_services(request: Request):
    get_request_actor(request)
    return {"services": build_services()}


@app.post("/api/services/register")
async def api_register_service(request: Request):
    actor = get_request_actor(request)
    if actor != "api-token":
        require_csrf(request)
    payload = ManagedServiceRegistration.model_validate(await request.json())
    registration = upsert_registration(payload, actor)
    return JSONResponse({"service": registration}, status_code=201)


@app.post("/api/services/{service_key}/action/{action}")
def api_service_action(request: Request, service_key: str, action: str):
    actor = get_request_actor(request)
    if actor != "api-token":
        require_csrf(request)
    service = act_on_service(service_key, action, actor)
    return {"service": service}
