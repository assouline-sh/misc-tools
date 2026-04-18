#!/usr/bin/env python3
"""
ctfdump.py — Scrape all challenges and files from a CTFd instance,
organized into: <ctf_name>/<category>/<challenge>/

Usage:
    python ctfdump.py <url> [-t TOKEN] [-c COOKIE] [-o OUTPUT_DIR]

Examples:
    # Using an API token (Settings -> Access Tokens in CTFd)
    python ctfdump.py https://ctf.example.com -t ctfd_xxxxxxxxxxxx

    # Using a session cookie (copy the 'session' cookie from your browser)
    python ctfdump.py https://ctf.example.com -c "eyJ1c2VyX2lkIjo..."

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


def make_session(token: str | None, cookie: str | None) -> requests.Session:
    s = requests.Session()
    s.headers.update({"User-Agent": "ctfd-pull/1.0", "Accept": "application/json"})
    if token:
        s.headers["Authorization"] = f"Token {token}"
    if cookie:
        s.cookies.set("session", cookie)
    return s


def api_get(session: requests.Session, base: str, path: str) -> dict:
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


def download_file(session: requests.Session, base: str, file_path: str, dest: Path) -> None:
    # file_path from the API looks like "/files/<hash>/<name>?token=..."
    url = urljoin(base, file_path)
    with session.get(url, stream=True, timeout=60) as r:
        r.raise_for_status()
        dest.parent.mkdir(parents=True, exist_ok=True)
        with open(dest, "wb") as f:
            for chunk in r.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)


def filename_from_path(file_path: str) -> str:
    # Strip query string and get the basename
    parsed = urlparse(file_path)
    return sanitize(os.path.basename(parsed.path) or "file")


def get_ctf_name(session: requests.Session, base: str) -> str:
    """Try to get the CTF name from the CTFd instance."""
    # Try the public config endpoint first (works on most CTFd versions)
    try:
        r = session.get(urljoin(base, "api/v1/configs/ctf_name"), timeout=10)
        if r.ok:
            data = r.json()
            name = data.get("data", {}).get("value", "")
            if name:
                return name
    except Exception:
        pass

    # Fallback: parse <title> from the homepage
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

    # Last resort: use the hostname
    return urlparse(base).hostname or "ctf"


def main() -> int:
    p = argparse.ArgumentParser(description="Download all CTFd challenge files, organized by challenge.")
    p.add_argument("url", help="Base URL of the CTFd instance (e.g. https://ctf.example.com)")
    p.add_argument("-t", "--token", help="CTFd API access token")
    p.add_argument("-c", "--cookie", help="CTFd 'session' cookie value")
    p.add_argument("-o", "--output", default=None, help="Output directory (default: auto-detected CTF name)")
    args = p.parse_args()

    if not args.token and not args.cookie:
        sys.exit("[!] Provide auth via --token or --cookie (most CTFd instances require login).")

    parsed = urlparse(args.url)
    base = f"{parsed.scheme}://{parsed.netloc}/"
    session = make_session(args.token, args.cookie)

    # Auto-detect CTF name for the output folder
    if args.output:
        out_root = Path(args.output)
    else:
        ctf_name = get_ctf_name(session, base)
        out_root = Path(sanitize(ctf_name))
        print(f"[*] CTF name: {ctf_name}")

    out_root.mkdir(parents=True, exist_ok=True)

    print(f"[*] Fetching challenge list from {base}")
    challenges = api_get(session, base, "api/v1/challenges")
    print(f"[*] Found {len(challenges)} challenges\n")

    total_files = 0
    for ch in challenges:
        cid = ch["id"]
        name = ch.get("name", f"challenge_{cid}")
        category = ch.get("category", "misc")

        # Fetch full challenge details (includes files + description)
        try:
            detail = api_get(session, base, f"api/v1/challenges/{cid}")
        except Exception as e:
            print(f"  [!] Failed to fetch challenge {cid} ({name}): {e}")
            continue

        chal_dir = out_root / sanitize(category) / sanitize(name)
        chal_dir.mkdir(parents=True, exist_ok=True)

        # Save challenge metadata as a README
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
            fname = filename_from_path(fp)
            dest = chal_dir / fname
            try:
                download_file(session, base, fp, dest)
                print(f"      -> {dest.relative_to(out_root)}")
                total_files += 1
            except Exception as e:
                print(f"      [!] Failed to download {fp}: {e}")

    print(f"\n[*] Done. Downloaded {total_files} file(s) into '{out_root}'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
