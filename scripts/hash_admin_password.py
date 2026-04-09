#!/usr/bin/env python3

import argparse
import base64
import getpass
import hashlib
import os


def build_hash(password: str, iterations: int) -> str:
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    salt_b64 = base64.b64encode(salt).decode("ascii")
    digest_b64 = base64.b64encode(digest).decode("ascii")
    return f"pbkdf2_sha256${iterations}${salt_b64}${digest_b64}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate ADMIN_PASSWORD_HASH for admin-control.")
    parser.add_argument("--password", help="Plain-text password. If omitted, the script prompts securely.")
    parser.add_argument("--iterations", type=int, default=600000, help="PBKDF2 iteration count.")
    args = parser.parse_args()

    password = args.password or getpass.getpass("Admin password: ")
    if not password:
        raise SystemExit("Password cannot be empty.")

    print(build_hash(password, args.iterations))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
