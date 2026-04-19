#!/usr/bin/env python3
"""
ctfdump.py — Scrape all challenges and files from a CTFd or rCTF instance,
organized into: <ctf_name>/<category>/<challenge>/

Usage:
    python ctfdump.py <url> [-t TOKEN] [-c COOKIE] [-o OUTPUT_DIR] [-p PLATFORM]

Examples:
    # CTFd: Using an API token (Settings -> Access Tokens in CTFd)
    python ctfdump.py https://ctf.example.com -t ctfd_xxxxxxxxxxxx

    # CTFd: Using a session cookie (copy the 'session' cookie from your browser)
    python ctfdump.py https://ctf.example.com -c "eyJ1c2VyX2lkIjo..."

    # rCTF: Using an auth token (e.g. from ctf_clearance cookie)
    python ctfdump.py https://ctf.squ1rrel.dev -t "TOKEN_VALUE"

    # Force platform detection
    python ctfdump.py https://ctf.example.com -t TOKEN -p rctf

    # Custom output directory (default: auto-detected CTF name)
    python ctfdump.py https://ctf.example.com -t TOKEN -o ./my_ctf
"""

import argparse
import os
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlparse

try:
    import requests
except ImportError:
    sys.exit("Missing dependency: pip install requests")


def sanitize(name: str) -> str:
    """Make a string safe for use as a folder/file name."""
    name = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", name).strip().strip(".")
    name = name.replace(" ", "_")
    return name[:150] or "unnamed"


# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------

def detect_platform(session: requests.Session, base: str) -> str:
    """Auto-detect whether the CTF is CTFd or rCTF."""
    # Try rCTF config endpoint
    try:
        r = session.get(urljoin(base, "api/v1/integrations/client/config"), timeout=10)
        if r.ok:
            data = r.json()
            if data.get("kind") == "goodClientConfig":
                return "rctf"
    except Exception:
        pass

    # Try CTFd endpoint
    try:
        r = session.get(urljoin(base, "api/v1/configs/ctf_name"), timeout=10)
        if r.ok:
            data = r.json()
            if "data" in data and "success" in data:
                return "ctfd"
    except Exception:
        pass

    # Fallback: check homepage for clues
    try:
        r = session.get(base, timeout=10)
        if r.ok:
            text = r.text.lower()
            if "rctf" in text or "redpwn" in text:
                return "rctf"
    except Exception:
        pass

    return "ctfd"


# ---------------------------------------------------------------------------
# CTFd backend
# ---------------------------------------------------------------------------

def ctfd_make_session(token: str | None, cookie: str | None) -> requests.Session:
    s = requests.Session()
    s.headers.update({"User-Agent": "ctfdump/1.0", "Accept": "application/json"})
    if token:
        s.headers["Authorization"] = f"Token {token}"
    if cookie:
        if ":" in cookie:
            cookie_name, cookie_value = cookie.split(":", 1)
            s.cookies.set(cookie_name, cookie_value)
        else:
            s.cookies.set("session", cookie)
    return s


def ctfd_api_get(session: requests.Session, base: str, path: str) -> dict:
    url = urljoin(base, path)
    r = session.get(url, timeout=30)
    if r.status_code == 403:
        sys.exit(f"[!] 403 Forbidden at {url} — CTF may not have started, or auth is invalid.")
    if r.status_code == 401:
        sys.exit(f"[!] 401 Unauthorized — check your token/cookie.")
    r.raise_for_status()
    data = r.json()
    if not data.get("success", True):
        sys.exit(f"[!] API error at {path}: {data}")
    return data.get("data", data)


def ctfd_get_name(session: requests.Session, base: str) -> str:
    try:
        r = session.get(urljoin(base, "api/v1/configs/ctf_name"), timeout=10)
        if r.ok:
            data = r.json()
            name = data.get("data", {}).get("value", "")
            if name:
                return name
    except Exception:
        pass
    return _get_name_from_title(session, base)


def ctfd_dump(session: requests.Session, base: str, out_root: Path) -> int:
    print(f"[*] Platform: CTFd")
    print(f"[*] Fetching challenge list from {base}")
    challenges = ctfd_api_get(session, base, "api/v1/challenges")
    print(f"[*] Found {len(challenges)} challenges\n")

    total_files = 0
    for ch in challenges:
        cid = ch["id"]
        name = ch.get("name", f"challenge_{cid}")
        category = ch.get("category", "misc")

        try:
            detail = ctfd_api_get(session, base, f"api/v1/challenges/{cid}")
        except Exception as e:
            print(f"  [!] Failed to fetch challenge {cid} ({name}): {e}")
            continue

        chal_dir = out_root / sanitize(category) / sanitize(name)
        chal_dir.mkdir(parents=True, exist_ok=True)

        readme = chal_dir / "README.md"
        with open(readme, "w", encoding="utf-8") as f:
            f.write(f"# {name}\n\n")
            f.write(f"**Category:** {category}\n\n")
            if "value" in detail:
                f.write(f"**Points:** {detail['value']}\n\n")
            if detail.get("description"):
                f.write("## Description\n\n")
                f.write(detail["description"] + "\n\n")
            if detail.get("connection_info"):
                f.write(f"## Connection\n\n`{detail['connection_info']}`\n\n")
            if detail.get("tags"):
                tags = ", ".join(t.get("value", str(t)) if isinstance(t, dict) else str(t) for t in detail["tags"])
                f.write(f"**Tags:** {tags}\n")

        files = detail.get("files", []) or []
        print(f"[+] {category}/{name}  ({len(files)} file{'s' if len(files) != 1 else ''})")

        for fp in files:
            fname = _filename_from_path(fp)
            dest = chal_dir / fname
            try:
                _download_file(session, base, fp, dest)
                print(f"      -> {dest.relative_to(out_root)}")
                total_files += 1
            except Exception as e:
                print(f"      [!] Failed to download {fp}: {e}")

    return total_files


# ---------------------------------------------------------------------------
# rCTF backend
# ---------------------------------------------------------------------------

def rctf_make_session(token: str | None, cookie: str | None) -> requests.Session:
    s = requests.Session()
    s.headers.update({"User-Agent": "ctfdump/1.0", "Accept": "application/json"})
    # rCTF uses Bearer auth. The token may come from the ctf_clearance cookie.
    auth_token = token
    if not auth_token and cookie:
        # If a cookie was provided, extract the value (might be name:value format)
        if ":" in cookie:
            _, auth_token = cookie.split(":", 1)
        else:
            auth_token = cookie
    if auth_token:
        s.headers["Authorization"] = f"Bearer {auth_token}"
    return s


def rctf_get_name(session: requests.Session, base: str) -> str:
    try:
        r = session.get(urljoin(base, "api/v1/integrations/client/config"), timeout=10)
        if r.ok:
            data = r.json()
            name = data.get("data", {}).get("ctfName", "")
            if name:
                return name
    except Exception:
        pass
    return _get_name_from_title(session, base)


def rctf_dump(session: requests.Session, base: str, out_root: Path) -> int:
    print(f"[*] Platform: rCTF")
    print(f"[*] Fetching challenge list from {base}")

    url = urljoin(base, "api/v1/challs")
    r = session.get(url, timeout=30)
    if r.status_code == 403:
        sys.exit(f"[!] 403 Forbidden — CTF may not have started, or auth is invalid.")
    if r.status_code == 401:
        sys.exit(f"[!] 401 Unauthorized — check your token/cookie.")
    r.raise_for_status()
    resp = r.json()

    if resp.get("kind") != "goodChallenges":
        sys.exit(f"[!] Unexpected response: {resp.get('kind', 'unknown')} — {resp.get('message', '')}")

    challenges = resp.get("data", [])
    print(f"[*] Found {len(challenges)} challenges\n")

    total_files = 0
    for ch in challenges:
        name = ch.get("name", ch.get("id", "unnamed"))
        category = ch.get("category", "misc")
        author = ch.get("author", "")

        chal_dir = out_root / sanitize(category) / sanitize(name)
        chal_dir.mkdir(parents=True, exist_ok=True)

        readme = chal_dir / "README.md"
        with open(readme, "w", encoding="utf-8") as f:
            f.write(f"# {name}\n\n")
            f.write(f"**Category:** {category}\n\n")
            if author:
                f.write(f"**Author:** {author}\n\n")
            if "points" in ch:
                f.write(f"**Points:** {ch['points']}\n\n")
            if "solves" in ch:
                f.write(f"**Solves:** {ch['solves']}\n\n")
            if ch.get("description"):
                f.write("## Description\n\n")
                f.write(ch["description"] + "\n\n")

        files = ch.get("files", []) or []
        print(f"[+] {category}/{name}  ({len(files)} file{'s' if len(files) != 1 else ''})")

        for file_info in files:
            if isinstance(file_info, dict):
                fname = sanitize(file_info.get("name", "file"))
                file_url = file_info.get("url", "")
            else:
                # Fallback if files are plain strings
                fname = _filename_from_path(str(file_info))
                file_url = str(file_info)

            if not file_url:
                continue

            dest = chal_dir / fname
            try:
                _download_file_url(session, file_url, dest)
                print(f"      -> {dest.relative_to(out_root)}")
                total_files += 1
            except Exception as e:
                print(f"      [!] Failed to download {fname}: {e}")

    return total_files


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def _get_name_from_title(session: requests.Session, base: str) -> str:
    try:
        r = session.get(base, timeout=10)
        r.raise_for_status()

        class TitleParser(HTMLParser):
            def __init__(self):
                super().__init__()
                self.in_title = False
                self.title = ""

            def handle_starttag(self, tag, attrs):
                if tag == "title":
                    self.in_title = True

            def handle_data(self, data):
                if self.in_title:
                    self.title += data

            def handle_endtag(self, tag):
                if tag == "title":
                    self.in_title = False

        parser = TitleParser()
        parser.feed(r.text)
        if parser.title.strip():
            return parser.title.strip()
    except Exception:
        pass
    return urlparse(base).hostname or "ctf"


def _filename_from_path(file_path: str) -> str:
    parsed = urlparse(file_path)
    return sanitize(os.path.basename(parsed.path) or "file")


def _download_file(session: requests.Session, base: str, file_path: str, dest: Path) -> None:
    url = urljoin(base, file_path)
    _download_file_url(session, url, dest)


def _download_file_url(session: requests.Session, url: str, dest: Path) -> None:
    with session.get(url, stream=True, timeout=60) as r:
        r.raise_for_status()
        dest.parent.mkdir(parents=True, exist_ok=True)
        with open(dest, "wb") as f:
            for chunk in r.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    p = argparse.ArgumentParser(description="Download all challenges from a CTFd or rCTF instance.")
    p.add_argument("url", help="Base URL of the CTF instance (e.g. https://ctf.example.com)")
    p.add_argument("-t", "--token", help="API/auth token")
    p.add_argument("-c", "--cookie", help="Session cookie value (or name:value)")
    p.add_argument("-o", "--output", default=None, help="Output directory (default: auto-detected CTF name)")
    p.add_argument("-p", "--platform", choices=["ctfd", "rctf"], default=None,
                   help="Force platform type (default: auto-detect)")
    args = p.parse_args()

    if not args.token and not args.cookie:
        sys.exit("[!] Provide auth via --token or --cookie.")

    parsed = urlparse(args.url)
    base = f"{parsed.scheme}://{parsed.netloc}/"

    # Create a basic session for platform detection
    detect_session = requests.Session()
    detect_session.headers.update({"User-Agent": "ctfdump/1.0", "Accept": "application/json"})

    platform = args.platform or detect_platform(detect_session, base)
    print(f"[*] Detected platform: {platform}")

    if platform == "rctf":
        session = rctf_make_session(args.token, args.cookie)
        if args.output:
            out_root = Path(args.output)
        else:
            ctf_name = rctf_get_name(session, base)
            out_root = Path(sanitize(ctf_name))
            print(f"[*] CTF name: {ctf_name}")
        out_root.mkdir(parents=True, exist_ok=True)
        total_files = rctf_dump(session, base, out_root)
    else:
        session = ctfd_make_session(args.token, args.cookie)
        if args.output:
            out_root = Path(args.output)
        else:
            ctf_name = ctfd_get_name(session, base)
            out_root = Path(sanitize(ctf_name))
            print(f"[*] CTF name: {ctf_name}")
        out_root.mkdir(parents=True, exist_ok=True)
        total_files = ctfd_dump(session, base, out_root)

    print(f"\n[*] Done. Downloaded {total_files} file(s) into '{out_root}'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
