#!/usr/bin/env python3
"""
spotiback — Weekly Spotify backup of playlists and followed artists.

Saves JSON snapshots with full track metadata + Spotify URIs so playlists
can be reconstructed. Each run creates a timestamped backup directory.

Setup:
    1. Create an app at https://developer.spotify.com/dashboard
    2. Set redirect URI to http://127.0.0.1:8888/callback
    3. Copy .env.example to .env and fill in your credentials
    4. Run once interactively to authorize:  python spotiback.py --auth
    5. Add to cron:  0 3 * * 0 cd /home/shan/github/misc-tools/spotiback && ./venv/bin/python spotiback.py

Restore:
    python spotiback.py --restore <backup_dir>
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

try:
    import spotipy
    from spotipy.oauth2 import SpotifyOAuth
except ImportError:
    sys.exit("Missing dependency: pip install spotipy")

SCRIPT_DIR = Path(__file__).resolve().parent
BACKUP_ROOT = SCRIPT_DIR / "backups"
CACHE_PATH = SCRIPT_DIR / ".spotify_cache"
SCOPES = "user-library-read playlist-read-private playlist-read-collaborative user-follow-read playlist-modify-public playlist-modify-private"


def load_env():
    env_file = SCRIPT_DIR / ".env"
    if not env_file.exists():
        sys.exit(f"[!] Missing {env_file} — copy .env.example and fill in your credentials.")
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip())


def get_spotify() -> spotipy.Spotify:
    load_env()
    auth = SpotifyOAuth(
        client_id=os.environ["SPOTIPY_CLIENT_ID"],
        client_secret=os.environ["SPOTIPY_CLIENT_SECRET"],
        redirect_uri=os.environ.get("SPOTIPY_REDIRECT_URI", "http://127.0.0.1:8888/callback"),
        scope=SCOPES,
        cache_path=str(CACHE_PATH),
        open_browser=False,
    )
    return spotipy.Spotify(auth_manager=auth)


def paginate(sp, results, key=None):
    """Keep hitting 'next' until Spotify stops giving us pages."""
    page = results if key is None else results[key]
    items = list(page["items"])
    while page["next"]:
        page = sp.next(page)
        if key:
            page = page[key]
        items.extend(page["items"])
    return items


def fetch_playlists(sp: spotipy.Spotify, user_id: str) -> list[dict]:
    raw = paginate(sp, sp.current_user_playlists(limit=50))
    playlists = []
    for pl in raw:
        if not pl or not pl.get("id"):
            print(f"  [~] Skipping empty playlist entry")
            continue
        total = pl.get("tracks", {}).get("total", "?") if isinstance(pl.get("tracks"), dict) else "?"
        print(f"  [+] {pl.get('name', '<unnamed>')}  ({total} tracks)")
        tracks = fetch_playlist_tracks(sp, pl["id"])
        owner_id = (pl.get("owner") or {}).get("id", "")
        playlists.append({
            "name": pl.get("name", ""),
            "id": pl["id"],
            "uri": pl.get("uri", ""),
            "description": pl.get("description", ""),
            "public": pl.get("public"),
            "collaborative": pl.get("collaborative", False),
            "owner": owner_id,
            "owned_by_me": owner_id == user_id,
            "snapshot_id": pl.get("snapshot_id", ""),
            "track_count": len(tracks),
            "tracks": tracks,
        })
    return playlists


def fetch_playlist_tracks(sp: spotipy.Spotify, playlist_id: str) -> list[dict]:
    try:
        raw = paginate(sp, sp.playlist_items(playlist_id, limit=100))
    except spotipy.exceptions.SpotifyException as e:
        if e.http_status == 429:
            retry = int(e.headers.get("Retry-After", 5))
            print(f"    [~] Rate limited, waiting {retry}s...")
            time.sleep(retry + 1)
            return fetch_playlist_tracks(sp, playlist_id)
        # 403/404 usually means Spotify-curated playlists (Daily Mix etc)
        # or deleted playlists that still show up. nothing we can do
        if e.http_status in (403, 404):
            print(f"    [~] Can't read tracks for {playlist_id} (HTTP {e.http_status}), skipping")
            return []
        raise

    tracks = []
    for item in raw:
        # some API versions return 'item' instead of 'track'
        t = item.get("item") or item.get("track")
        if not t or not t.get("uri"):
            continue
        # local files have spotify:local: URIs — can't restore those
        if t["uri"].startswith("spotify:local:"):
            continue
        album = t.get("album") or {}
        tracks.append({
            "name": t.get("name", ""),
            "uri": t["uri"],
            "id": t.get("id"),
            "artists": [{"name": a.get("name", ""), "uri": a.get("uri", "")} for a in t.get("artists", [])],
            "album": {"name": album.get("name", ""), "uri": album.get("uri", "")} if album else None,
            "duration_ms": t.get("duration_ms"),
            "url": t.get("external_urls", {}).get("spotify", ""),
            "added_at": item.get("added_at", ""),
        })
    return tracks


def fetch_followed_artists(sp: spotipy.Spotify) -> list[dict]:
    """Uses cursor-based pagination (different from the rest of the API, of course)."""
    artists = []
    results = sp.current_user_followed_artists(limit=50)
    page = results["artists"]
    artists.extend(page["items"])
    while page["cursors"] and page["cursors"].get("after"):
        results = sp.current_user_followed_artists(limit=50, after=page["cursors"]["after"])
        page = results["artists"]
        artists.extend(page["items"])

    return [{
        "name": a["name"],
        "uri": a["uri"],
        "id": a["id"],
        "genres": a.get("genres", []),
        "url": a.get("external_urls", {}).get("spotify", ""),
    } for a in artists]


def fetch_liked_songs(sp: spotipy.Spotify) -> list[dict]:
    raw = paginate(sp, sp.current_user_saved_tracks(limit=50))
    tracks = []
    for item in raw:
        t = item.get("track")
        if not t or not t.get("uri"):
            continue
        tracks.append({
            "name": t["name"],
            "uri": t["uri"],
            "id": t.get("id"),
            "artists": [{"name": a["name"], "uri": a["uri"]} for a in t.get("artists", [])],
            "album": {"name": t["album"]["name"], "uri": t["album"]["uri"]} if t.get("album") else None,
            "added_at": item.get("added_at", ""),
            "url": t.get("external_urls", {}).get("spotify", ""),
        })
    return tracks


def do_backup(sp: spotipy.Spotify):
    user = sp.current_user()
    user_id = user["id"]
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d_%H%M%S")
    backup_dir = BACKUP_ROOT / timestamp
    backup_dir.mkdir(parents=True, exist_ok=True)

    print(f"[*] Backing up Spotify for user: {user['display_name']} ({user_id})")
    print(f"[*] Backup directory: {backup_dir}\n")

    print("[*] Fetching playlists...")
    playlists = fetch_playlists(sp, user_id)
    (backup_dir / "playlists.json").write_text(
        json.dumps(playlists, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(f"[*] Saved {len(playlists)} playlists\n")

    print("[*] Fetching followed artists...")
    artists = fetch_followed_artists(sp)
    (backup_dir / "followed_artists.json").write_text(
        json.dumps(artists, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(f"[*] Saved {len(artists)} followed artists\n")

    print("[*] Fetching liked songs...")
    liked = fetch_liked_songs(sp)
    (backup_dir / "liked_songs.json").write_text(
        json.dumps(liked, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(f"[*] Saved {len(liked)} liked songs\n")

    summary = {
        "timestamp": timestamp,
        "user_id": user_id,
        "display_name": user["display_name"],
        "playlist_count": len(playlists),
        "followed_artist_count": len(artists),
        "liked_song_count": len(liked),
        "total_playlist_tracks": sum(p["track_count"] for p in playlists),
    }
    (backup_dir / "summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    # point "latest" symlink at this backup so cron scripts can find it
    latest = BACKUP_ROOT / "latest"
    if latest.is_symlink() or latest.exists():
        latest.unlink()
    latest.symlink_to(backup_dir.name)

    print(f"[*] Done. Backup saved to {backup_dir}")
    print(f"    {summary['playlist_count']} playlists, "
          f"{summary['total_playlist_tracks']} tracks, "
          f"{summary['liked_song_count']} liked songs, "
          f"{summary['followed_artist_count']} artists")


def do_restore(sp: spotipy.Spotify, backup_dir: Path):
    user = sp.current_user()
    user_id = user["id"]

    playlists_file = backup_dir / "playlists.json"
    if not playlists_file.exists():
        sys.exit(f"[!] No playlists.json found in {backup_dir}")

    playlists = json.loads(playlists_file.read_text(encoding="utf-8"))
    print(f"[*] Restoring {len(playlists)} playlists for {user['display_name']}\n")

    for pl in playlists:
        # can't recreate someone else's playlist, just re-follow it
        if not pl["owned_by_me"]:
            print(f"  [~] Skipping '{pl['name']}' (not owned by you, following it instead)")
            try:
                sp.current_user_follow_playlist(pl["id"])
            except Exception:
                print(f"      [!] Could not follow playlist '{pl['name']}'")
            continue

        track_uris = [t["uri"] for t in pl["tracks"] if t.get("uri")]
        print(f"  [+] Creating '{pl['name']}' ({len(track_uris)} tracks)")

        new_pl = sp.user_playlist_create(
            user_id,
            pl["name"],
            public=pl.get("public", False),
            collaborative=pl.get("collaborative", False),
            description=pl.get("description", ""),
        )

        # spotify caps at 100 tracks per request
        for i in range(0, len(track_uris), 100):
            batch = track_uris[i:i + 100]
            try:
                sp.playlist_add_items(new_pl["id"], batch)
            except spotipy.exceptions.SpotifyException as e:
                if e.http_status == 429:
                    retry = int(e.headers.get("Retry-After", 5))
                    time.sleep(retry + 1)
                    sp.playlist_add_items(new_pl["id"], batch)
                else:
                    print(f"      [!] Failed to add batch: {e}")

    # re-follow artists
    artists_file = backup_dir / "followed_artists.json"
    if artists_file.exists():
        artists = json.loads(artists_file.read_text(encoding="utf-8"))
        print(f"\n[*] Re-following {len(artists)} artists...")
        artist_ids = [a["id"] for a in artists if a.get("id")]
        # also capped at 50 per request
        for i in range(0, len(artist_ids), 50):
            batch = artist_ids[i:i + 50]
            try:
                sp.user_follow_artists(batch)
            except Exception as e:
                print(f"  [!] Failed to follow batch: {e}")

    # re-like songs
    liked_file = backup_dir / "liked_songs.json"
    if liked_file.exists():
        liked = json.loads(liked_file.read_text(encoding="utf-8"))
        liked_ids = [t["id"] for t in liked if t.get("id")]
        print(f"[*] Re-liking {len(liked_ids)} songs...")
        for i in range(0, len(liked_ids), 50):
            batch = liked_ids[i:i + 50]
            try:
                sp.current_user_saved_tracks_add(batch)
            except Exception as e:
                print(f"  [!] Failed to like batch: {e}")

    print("\n[*] Restore complete!")


def main():
    p = argparse.ArgumentParser(description="Back up and restore Spotify playlists and followed artists.")
    p.add_argument("--auth", action="store_true", help="Run interactive auth flow (do this once)")
    p.add_argument("--restore", metavar="DIR", help="Restore from a backup directory")
    args = p.parse_args()

    sp = get_spotify()

    if args.auth:
        user = sp.current_user()
        print(f"[*] Authenticated as: {user['display_name']} ({user['id']})")
        print(f"[*] Token cached at: {CACHE_PATH}")
        print("[*] You can now run spotiback from cron.")
        return

    if args.restore:
        do_restore(sp, Path(args.restore))
    else:
        do_backup(sp)


if __name__ == "__main__":
    main()
