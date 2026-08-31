#!/usr/bin/env python3
"""Upload IPA/APK to PGYER (API v2 COS token flow).

Usage:
  PGYER_API_KEY=xxx python scripts/pgyer_upload.py path/to/app.ipa
  PGYER_API_KEY=xxx python scripts/pgyer_upload.py path/to/app.apk android
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request


def post_form(url: str, data: dict[str, str]) -> dict:
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode())


def main() -> int:
    api_key = os.environ.get("PGYER_API_KEY", "").strip()
    if not api_key:
        print("PGYER_API_KEY missing", file=sys.stderr)
        return 1
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} <file> [ios|android]", file=sys.stderr)
        return 1

    path = sys.argv[1]
    build_type = sys.argv[2] if len(sys.argv) > 2 else (
        "android" if path.lower().endswith(".apk") else "ios"
    )
    if not os.path.isfile(path):
        print(f"file not found: {path}", file=sys.stderr)
        return 1

    print(f"PGYER getCOSToken ({build_type}) ...")
    token = post_form(
        "https://www.pgyer.com/apiv2/app/getCOSToken",
        {
            "_api_key": api_key,
            "buildType": build_type,
            "buildInstallType": "1",
        },
    )
    if token.get("code") != 0:
        print(json.dumps(token, ensure_ascii=False), file=sys.stderr)
        return 1

    data = token["data"]
    endpoint = data["endpoint"]
    build_key = data["key"]
    params = data.get("params") or {}

    curl_cmd = ["curl", "-s", "-S", "-f", "-X", "POST", endpoint, "-F", f"key={build_key}"]
    for k, v in params.items():
        curl_cmd.extend(["-F", f"{k}={v}"])
    curl_cmd.extend(["-F", f"file=@{path}"])

    print(f"PGYER uploading {path} ...")
    proc = subprocess.run(curl_cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        print(proc.stderr or proc.stdout or "upload failed", file=sys.stderr)
        return 1

    print("PGYER waiting for buildInfo ...")
    for attempt in range(1, 61):
        info = post_form(
            "https://www.pgyer.com/apiv2/app/buildInfo",
            {"_api_key": api_key, "buildKey": build_key},
        )
        if info.get("code") == 0:
            bd = info.get("data") or {}
            url = (
                bd.get("buildShortcutUrl")
                or bd.get("buildQRCodeURL")
                or bd.get("buildDownloadUrl")
                or ""
            )
            if url:
                print(f"PGYER_URL={url}")
                summary = os.environ.get("GITHUB_STEP_SUMMARY")
                if summary:
                    with open(summary, "a", encoding="utf-8") as f:
                        f.write("## 蒲公英安装\n\n")
                        f.write(f"- 安装页：[{url}]({url})\n")
                        if bd.get("buildVersion"):
                            f.write(f"- 版本：{bd.get('buildVersion')}\n")
                        if bd.get("buildBuildVersion"):
                            f.write(f"- Build：{bd.get('buildBuildVersion')}\n")
                return 0
        time.sleep(2)
        if attempt % 5 == 0:
            print(f"  still processing ({attempt * 2}s) ...")

    print("buildInfo timeout", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
