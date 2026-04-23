#!/usr/bin/env python3
"""
Ensure a LiteLLM user exists for the given email. Creates one if not found.

Required env vars:
  LITELLM_API_URL         - Base URL, e.g. http://litellm:4000
  LITELLM_API_KEY  - Master API key

Email resolved from (first match):
  1. CLI arg
  2. CODER_WORKSPACE_OWNER_EMAIL
  3. USER_EMAIL
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def get_headers(api_key: str) -> dict:
    return {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }


def find_user(base_url: str, api_key: str, email: str) -> dict | None:
    params = urllib.parse.urlencode({"user_email": email, "page_size": 10})
    url = f"{base_url}/user/list?{params}"
    req = urllib.request.Request(url, headers=get_headers(api_key))
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
            users = data.get("users", [])
            for user in users:
                if user.get("user_email", "").lower() == email.lower():
                    return user
    except urllib.error.HTTPError as e:
        print(f"ERROR: GET /user/list returned {e.code}: {e.read().decode()}", file=sys.stderr)
        sys.exit(1)
    return None


def create_user(base_url: str, api_key: str, email: str) -> dict:
    url = f"{base_url}/user/new"
    payload = json.dumps({"user_email": email, "user_role": "internal_user", "auto_create_key": False}).encode()
    req = urllib.request.Request(url, data=payload, headers=get_headers(api_key), method="POST")
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"ERROR: POST /user/new returned {e.code}: {e.read().decode()}", file=sys.stderr)
        sys.exit(1)


def create_key(base_url: str, api_key: str, user_id: str, key_alias: str | None = None) -> dict:
    url = f"{base_url}/key/generate"
    payload: dict = {"user_id": user_id}
    if key_alias:
        payload["key_alias"] = key_alias
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode(), headers=get_headers(api_key), method="POST"
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"ERROR: POST /key/generate returned {e.code}: {e.read().decode()}", file=sys.stderr)
        sys.exit(1)


def main():
    base_url = os.environ.get("LITELLM_API_URL", "").rstrip("/")
    api_key = os.environ.get("LITELLM_API_KEY", "")

    if not base_url:
        print("ERROR: LITELLM_API_URL not set", file=sys.stderr)
        sys.exit(1)
    if not api_key:
        print("ERROR: LITELLM_API_KEY not set", file=sys.stderr)
        sys.exit(1)

    if len(sys.argv) > 1:
        email = sys.argv[1]
    else:
        email = (
            os.environ.get("CODER_WORKSPACE_OWNER_EMAIL")
            or os.environ.get("USER_EMAIL")
        )

    if not email:
        print(
            "ERROR: no email provided — pass as arg or set CODER_WORKSPACE_OWNER_EMAIL / USER_EMAIL",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"Checking LiteLLM for user: {email}")
    user = find_user(base_url, api_key, email)

    if user:
        user_id = user.get("user_id")
        print(f"User exists: {user_id}")
    else:
        print("User not found — creating...")
        result = create_user(base_url, api_key, email)
        user_id = result.get("user_id")
        print(f"Created user: {user_id}")

    print("Creating key...")
    key_result = create_key(base_url, api_key, user_id)
    print(key_result.get("key"))


if __name__ == "__main__":
    main()
