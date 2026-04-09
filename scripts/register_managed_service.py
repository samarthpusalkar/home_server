#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_DIR = SCRIPT_DIR.parent
SEED_FILE = REPO_DIR / "config" / "admin-control" / "registry.seed.json"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def normalize_key(value: str) -> str:
    allowed = []
    for char in value.strip().lower():
        if char.isalnum() or char in {"-", "_"}:
            allowed.append(char)
        elif char in {" ", "."}:
            allowed.append("-")
    key = "".join(allowed).strip("-_")
    if not key:
        raise SystemExit("Service key must include letters or numbers.")
    return key


def ensure_registry_file(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        path.write_text(SEED_FILE.read_text(encoding="utf-8"), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Register or update a managed service entry.")
    parser.add_argument("--state-dir", required=True, help="Directory containing the registry and state files.")
    parser.add_argument("--key", required=True, help="Stable service key.")
    parser.add_argument("--display-name", required=True, help="Human-readable service name.")
    parser.add_argument("--container-name", required=True, help="Exact Docker container name.")
    parser.add_argument("--description", default="", help="Short description shown in the admin panel.")
    parser.add_argument("--exposure", default="custom", help="Exposure type like traefik, playit, or local-only.")
    parser.add_argument(
        "--public-host",
        action="append",
        default=[],
        help="Public hostname for the service. Repeat for multiple hosts.",
    )
    parser.add_argument(
        "--default-auto-start",
        choices={"true", "false"},
        default="true",
        help="Default auto-start value when no explicit state has been stored yet.",
    )
    parser.add_argument(
        "--protected",
        choices={"true", "false"},
        default="false",
        help="Mark a service as visible-but-protected in the UI.",
    )
    parser.add_argument("--updated-by", default="script", help="Actor name recorded in the registry.")
    args = parser.parse_args()

    state_dir = Path(args.state_dir).expanduser()
    registry_file = state_dir / "service-registry.json"
    ensure_registry_file(registry_file)

    raw = json.loads(registry_file.read_text(encoding="utf-8"))
    services = {
        service["key"]: service
        for service in raw.get("services", [])
        if isinstance(service, dict) and service.get("key") and service.get("key") != "cloudflared"
    }

    key = normalize_key(args.key)
    services[key] = {
      "key": key,
      "display_name": args.display_name.strip(),
      "container_name": args.container_name.strip(),
      "description": args.description.strip(),
      "exposure": args.exposure.strip() or "custom",
      "public_hosts": sorted({host.strip() for host in args.public_host if host.strip()}),
      "default_auto_start": args.default_auto_start == "true",
      "protected": args.protected == "true",
      "updated_at": utc_now(),
      "updated_by": args.updated_by,
    }

    payload = {"version": 1, "services": [services[name] for name in sorted(services)]}
    registry_file.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Registered managed service '{key}' in {registry_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
