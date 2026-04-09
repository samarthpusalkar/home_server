#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=False, capture_output=True, text=True)


def docker_cmd(prefix: str | None, *parts: str) -> list[str]:
    cmd: list[str] = []
    if prefix:
        cmd.append(prefix)
    cmd.append("docker")
    cmd.extend(parts)
    return cmd


def main() -> int:
    parser = argparse.ArgumentParser(description="Stop services whose auto-start is disabled.")
    parser.add_argument("--state-dir", required=True, help="Directory containing service-state.json.")
    parser.add_argument("--docker-prefix", default="", help="Optional command prefix like sudo.")
    args = parser.parse_args()

    state_dir = Path(args.state_dir).expanduser()
    state_file = state_dir / "service-state.json"
    registry_file = state_dir / "service-registry.json"
    if not state_file.exists():
        print(f"[reconcile] No state file at {state_file}; nothing to reconcile.")
        return 0

    payload = json.loads(state_file.read_text(encoding="utf-8"))
    services = payload.get("services", {})
    disabled = {
        key: value
        for key, value in services.items()
        if isinstance(value, dict) and value.get("auto_start") is False
    }

    if not disabled:
        print("[reconcile] No disabled services recorded.")
        return 0

    registry: dict[str, dict[str, object]] = {}
    if registry_file.exists():
        raw_registry = json.loads(registry_file.read_text(encoding="utf-8"))
        registry = {
            service["key"]: service
            for service in raw_registry.get("services", [])
            if isinstance(service, dict) and service.get("key")
        }

    container_listing = run(docker_cmd(args.docker_prefix or None, "ps", "-a", "--format", "{{.Names}}"))
    if container_listing.returncode != 0:
        print(container_listing.stderr.strip() or "[reconcile] Failed to query Docker containers.")
        return container_listing.returncode

    existing = {line.strip() for line in container_listing.stdout.splitlines() if line.strip()}
    for service_key in sorted(disabled):
        container_name = str(registry.get(service_key, {}).get("container_name") or service_key)
        if container_name not in existing:
            print(f"[reconcile] Skipping {service_key}; container '{container_name}' is not present.")
            continue
        result = run(docker_cmd(args.docker_prefix or None, "stop", container_name))
        if result.returncode == 0:
            print(f"[reconcile] Stopped disabled service: {service_key} ({container_name})")
        else:
            stderr = result.stderr.strip() or result.stdout.strip()
            print(f"[reconcile] Failed to stop {service_key} ({container_name}): {stderr}")
            return result.returncode

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
