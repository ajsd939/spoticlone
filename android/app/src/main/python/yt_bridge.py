import json

import yt_dlp
from ytmusicapi import YTMusic
from ytmusicapi.continuations import get_continuations

# Warmed up once from App.onCreate (background thread). Keep one instance.
_ytm = YTMusic()


def _coerce_str(v, fallback=""):
    try:
        if v is None:
            return fallback
        s = str(v).strip()
        return s if s else fallback
    except Exception:
        return fallback


def _coerce_int(v):
    try:
        return int(v or 0)
    except Exception:
        return 0


def search_music(query, limit=30):
    """Unfiltered YouTube Music search: artists + albums + songs.

    A songs-only filter can never surface artists (spec: the search
    bar must know about artists). One unfiltered call ranks the
    artist itself first for artist queries, like Spotify's top result.
    Returns {"songs": [...], "artists": [...], "albums": [...]}.
    """
    out_songs, out_artists, out_albums = [], [], []
    try:
        results = _ytm.search(query, limit=limit) or []
    except Exception as e:
        return json.dumps({"error": str(e)})
    for r in results:
        try:
            if not isinstance(r, dict):
                continue
            rtype = str(r.get("resultType") or "").lower()
            if rtype in ("song", "video"):
                item = _song_item(r)
                if item["videoId"]:
                    out_songs.append(item)
            elif rtype == "artist":
                # NOTE: the "Top result" artist card carries no
                # browseId/title; the id+name live in artists[0].
                bid = _coerce_str(r.get("browseId"))
                name = _coerce_str(r.get("title"))
                sub = r.get("artists") or []
                if sub and isinstance(sub[0], dict):
                    if not bid:
                        bid = _coerce_str(sub[0].get("id"))
                    if not name:
                        name = _coerce_str(sub[0].get("name"))
                if not name:
                    # Related-artist cards carry the name here.
                    name = _coerce_str(r.get("artist"))
                if not bid:
                    continue
                out_artists.append({
                    "artistId": bid,
                    "name": name or "Unknown",
                    "artworkUrl": _thumb(r.get("thumbnails")),
                })
            elif rtype in ("album", "single"):
                item = _collection_item(r)
                if item["albumId"]:
                    out_albums.append(item)
            # playlists etc. are skipped: no endpoint wired for them
        except Exception:
            continue
    return json.dumps({
        "songs": out_songs,
        "artists": out_artists,
        "albums": out_albums,
    })


def get_stream(query, video_id=""):
    """Resolve a direct audio stream URL via yt-dlp. No download.

    Prefers the exact video chosen in search results (video_id): what
    you tap is what plays, with no re-search drift into full-album
    uploads, lyric compilations or skit/interlude videos. Falls back
    to ytsearch1 when no id was supplied.
    Returns a JSON STRING for the same bridge-marshaling reason.
    googlevideo URLs expire in hours -> call at play-time, never cache.
    """
    vid = (video_id or "").strip()
    if len(vid) == 11 and vid.replace("-", "").replace("_", "").isalnum():
        target = f"https://www.youtube.com/watch?v={vid}"
    else:
        target = f"ytsearch1:{query}"
    base_opts = {
        "format": "bestaudio[ext=m4a]/bestaudio/best",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "skip_download": True,
        "extract_flat": False,
    }
    # YouTube throttles default-client URLs (~30 KB/s -> rebuffering
    # every few seconds). The android client serves full speed, so try
    # it first and fall back to default clients when it yields nothing
    # (SABR-only sessions) to preserve availability.
    last_err = "no stream URL"
    for extra in ({"youtube": {"player_client": ["android"]}}, None):
        try:
            opts = dict(base_opts)
            if extra:
                opts["extractor_args"] = extra
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(target, download=False)
            e = info["entries"][0] if "entries" in info else info
            url = _coerce_str(e.get("url"))
            if not url:
                last_err = "empty stream URL"
                continue
            return json.dumps({
                "url": url,
                "videoId": _coerce_str(e.get("id")),
                "title": _coerce_str(e.get("title")),
                "duration": _coerce_int(e.get("duration")),
            })
        except Exception as e:
            last_err = str(e)
            continue
    return json.dumps({"error": last_err})


def call(method, query, video_id=""):
    """Single lowercase entry point for the Kotlin bridge.

    Chaquopy lowercases attribute names in callAttr, so camelCase
    lookups like getStream arrive as getstream and miss. Kotlin
    only ever calls this function (plus the meanwhile-working
    search_music), keeping case-sensitive names out of the bridge.
    """
    try:
        m = str(method or "").lower()
        if m == "getstream":
            return get_stream(query, video_id)
        if m == "song":
            return get_song_details(video_id)
        if m in ("search", "search_music"):
            return search_music(query)
        if m == "artist":
            return get_artist(video_id)
        if m == "album":
            return get_album(video_id)
        return json.dumps({"error": "unknown method: " + m})
    except Exception as e:
        return json.dumps({"error": str(e)})


def _thumb(items):
    """Last (largest) thumbnail URL from a ytmusicapi thumbnail list."""
    try:
        if items and isinstance(items[-1], dict):
            return _coerce_str(items[-1].get("url"))
    except Exception:
        pass
    return ""


def _song_item(r, fallback_art=""):
    """Normalize a ytmusicapi song/video dict into a Track JSON dict."""
    artists = r.get("artists") or []
    names = [_coerce_str(a.get("name"))
             for a in artists if isinstance(a, dict)]
    names = [n for n in names if n]
    artist_id = ""
    if artists and isinstance(artists[0], dict):
        artist_id = _coerce_str(artists[0].get("id"))
    album = r.get("album")
    album_name = ""
    if isinstance(album, dict):
        album_name = _coerce_str(album.get("name"))
    return {
        "videoId": _coerce_str(r.get("videoId")),
        "title": _coerce_str(r.get("title"), "Unknown"),
        "artist": ", ".join(names) or "Unknown",
        "artistId": artist_id,
        "album": album_name,
        "artworkUrl": _thumb(r.get("thumbnails")) or fallback_art,
        "durationSec": _coerce_int(
            r.get("duration_seconds") if r.get("duration_seconds") is not None
            else r.get("duration")),
    }


def _collection_item(r):
    """Normalize an album/single/playlist dict into a summary dict."""
    return {
        "albumId": _coerce_str(r.get("browseId")),
        "title": _coerce_str(r.get("title"), "Unknown"),
        "year": _coerce_str(r.get("year")),
        "artworkUrl": _thumb(r.get("thumbnails")),
    }


def get_artist(artist_id):
    """Artist page: header, top tracks, ALL albums, ALL singles.

    get_artist() only returns a ~10-item preview per section, so the
    full lists are fetched via get_artist_albums() with each section's
    params (with graceful fallback to the preview on failure).
    Returns a JSON string.
    """
    try:
        a = _ytm.get_artist(artist_id or "") or {}
    except Exception as e:
        return json.dumps({"error": str(e)})
    try:
        channel = _coerce_str(a.get("channelId")) or str(artist_id or "")
        songs = _section_results(a.get("songs"))
        albums_info = a.get("albums") or {}
        singles_info = a.get("singles") or {}
        albums = [r for r in _section_results(albums_info)
                  if isinstance(r, dict)]
        singles = [r for r in _section_results(singles_info)
                   if isinstance(r, dict)]
        # Full discography via the section browse endpoint (the
        # library's get_artist_albums can't parse current responses).
        # Preview is kept as fallback if the full fetch fails.
        albums_norm = [_collection_item(r) for r in albums]
        try:
            sec_bid = _coerce_str(albums_info.get("browseId"))
            if sec_bid and albums_info.get("params"):
                full = _fetch_section_items(sec_bid,
                                            albums_info["params"])
                if full:
                    albums_norm = full
        except Exception:
            pass
        singles_norm = [_collection_item(r) for r in singles]
        try:
            sec_bid = _coerce_str(singles_info.get("browseId"))
            if sec_bid and singles_info.get("params"):
                full = _fetch_section_items(sec_bid,
                                            singles_info["params"])
                if full:
                    singles_norm = full
        except Exception:
            pass
        return json.dumps({
            "artistId": _coerce_str(a.get("channelId") or artist_id),
            "name": _coerce_str(a.get("name"), "Unknown"),
            "artworkUrl": _thumb(a.get("thumbnails")),
            "topTracks": [_song_item(r) for r in songs
                          if isinstance(r, dict)][:10],
            "albums": albums_norm,
            "singles": singles_norm,
        })
    except Exception as e:
        return json.dumps({"error": str(e)})


def get_album(album_id):
    """Album page: header + full track list. JSON string."""
    try:
        a = _ytm.get_album(album_id or "") or {}
    except Exception as e:
        return json.dumps({"error": str(e)})
    try:
        artists = a.get("artists") or []
        names = [_coerce_str(x.get("name"))
                 for x in artists if isinstance(x, dict)]
        names = [n for n in names if n]
        art = _thumb(a.get("thumbnails"))
        tracks = [ _song_item(r, fallback_art=art)
                   for r in (a.get("tracks") or [])
                   if isinstance(r, dict) ]
        return json.dumps({
            "albumId": _coerce_str(album_id),
            "title": _coerce_str(a.get("title"), "Unknown"),
            "artist": ", ".join(names) or "Unknown",
            "year": _coerce_str(a.get("year")),
            "artworkUrl": art,
            "tracks": tracks,
        })
    except Exception as e:
        return json.dumps({"error": str(e)})


def _section_results(section):
    """Track/album preview list tolerating dict- or list-shaped payloads."""
    if isinstance(section, dict):
        return section.get("results") or []
    if isinstance(section, list):
        return section
    return []


def get_song_details(video_id):
    """Fill gaps for search items missing artist/duration (ATV uploads).

    videoDetails carries the clean title, real author, channel id and
    true length. JSON string like everything else on the bridge.
    """
    try:
        d = _ytm.get_song(video_id or "") or {}
    except Exception as e:
        return json.dumps({"error": str(e)})
    try:
        vd = d.get("videoDetails") or {}
        author = _coerce_str(vd.get("author"))
        # "Artist - Topic" auto-channels -> plain artist name.
        if author.lower().endswith(" - topic"):
            author = author[: -len(" - topic")].strip()
        dur = 0
        try:
            dur = int(str(vd.get("lengthSeconds") or 0))
        except Exception:
            dur = 0
        return json.dumps({
            "videoId": _coerce_str(vd.get("videoId") or video_id),
            "title": _coerce_str(vd.get("title")),
            "artist": author,
            "artistId": _coerce_str(vd.get("channelId")),
            "duration": dur,
        })
    except Exception as e:
        return json.dumps({"error": str(e)})


def _grid_album(item):
    """Normalize one musicTwoRowItemRenderer (album/single grid cell)."""
    r = (item or {}).get("musicTwoRowItemRenderer") or {}
    runs = (r.get("title") or {}).get("runs") or []
    title = runs[0].get("text", "") if runs else ""
    year = ""
    for s in reversed((r.get("subtitle") or {}).get("runs") or []):
        t = _coerce_str(s.get("text"))
        if len(t) == 4 and t.isdigit():
            year = t
            break
    bid = (((r.get("navigationEndpoint") or {})
             .get("browseEndpoint")) or {}).get("browseId") or ""
    thumbs = ((((r.get("thumbnailRenderer") or {})
                .get("musicThumbnailRenderer")) or {})
              .get("thumbnail") or {}).get("thumbnails") or []
    art = thumbs[-1].get("url", "") if thumbs else ""
    return {
        "albumId": _coerce_str(bid),
        "title": _coerce_str(title, "Unknown"),
        "year": year,
        "artworkUrl": _coerce_str(art),
    }


def _fetch_section_items(section_browse_id, params):
    """Complete album/single list for an artist section.

    Browses the section directly (always a gridRenderer) and follows
    grid continuations with the library's own machinery. Raises on any
    failure so the caller can fall back to the 10-item preview; a
    partial page (>= 1 item) is returned, never empty.
    """
    body = {"browseId": section_browse_id, "params": params}
    resp = _ytm._send_request("browse", body)
    scr = ((resp.get("contents") or {})
           .get("singleColumnBrowseResultsRenderer") or {})
    tabs = scr.get("tabs") or []
    tab = (tabs[0].get("tabRenderer") or {}) if tabs else {}
    content = ((tab.get("content") or {})
               .get("sectionListRenderer") or {}).get("contents") or []
    grid = next((s.get("gridRenderer") for s in content
                 if isinstance(s, dict) and "gridRenderer" in s), None)
    if grid is None:
        raise ValueError("no gridRenderer in section response")
    out = []
    for it in grid.get("items") or []:
        # One odd cell must not abort the whole discography fetch.
        try:
            alb = _grid_album(it)
        except Exception:
            continue
        if alb["albumId"]:
            out.append(alb)
    # Follow further pages (e.g. huge discographies). The helper
    # walks every continuation until none remain.
    request_func = (lambda additionalParams:
                    _ytm._send_request("browse", body, additionalParams))
    try:
        more = get_continuations(
            grid, "gridContinuation", None, request_func,
            lambda items: [_grid_album(i) for i in (items or [])])
        for alb in more or []:
            if isinstance(alb, dict) and alb.get("albumId"):
                out.append(alb)
    except Exception:
        pass  # keep the first page
    if not out:
        raise ValueError("empty section")
    return out
