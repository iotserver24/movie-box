import os
import time
import json
import requests
from fastapi import FastAPI, HTTPException, Query, Header, Depends
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="Nexastream / MovieBox Backend", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

API_TOKEN = os.getenv("API_TOKEN", "")

def verify_token(authorization: str = Header(default="")):
    if API_TOKEN:
        token = authorization.replace("Bearer ", "").strip()
        if token != API_TOKEN:
            raise HTTPException(status_code=401, detail="Unauthorized")
    return True

UPSTREAM_BASE = "https://themoviebox.xyz"
H5_API_BASE = "https://themoviebox.xyz/wefeed-h5api-bff"

DEFAULT_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Referer": f"{UPSTREAM_BASE}/",
    "X-Request-Lang": "en",
}

session = requests.Session()
session.headers.update(DEFAULT_HEADERS)

_guest_token_cache = {"token": None, "expires": 0}

def get_guest_token() -> str:
    now = time.time()
    if _guest_token_cache["token"] and _guest_token_cache["expires"] > now:
        return _guest_token_cache["token"]
    try:
        resp = session.get(
            f"{H5_API_BASE}/subject/trending",
            params={"page": 1, "perPage": 1, "host": "themoviebox.xyz"},
            timeout=10,
        )
        x_user = resp.headers.get("x-user")
        if x_user:
            token = json.loads(x_user).get("token")
            if token:
                _guest_token_cache["token"] = token
                _guest_token_cache["expires"] = now + 300
                return token
        token = session.cookies.get("token")
        if token:
            _guest_token_cache["token"] = token
            _guest_token_cache["expires"] = now + 300
            return token
    except Exception:
        pass
    return ""

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/v1/home")
def get_home(_ = Depends(verify_token)):
    try:
        res = session.get(f"{H5_API_BASE}/home", params={"host": "themoviebox.xyz"}, timeout=15)
        if res.status_code == 200:
            return res.json().get("data", {"banners": [], "sections": []})
    except Exception:
        pass
    return {"banners": [], "sections": []}

@app.get("/v1/catalog/{name}")
def get_catalog(name: str, page: int = 1, _ = Depends(verify_token)):
    try:
        channels = {"movies": 1, "series": 2, "animation": 1006}
        channel_id = channels.get(name, 1)
        res = session.post(
            f"{H5_API_BASE}/subject/filter",
            json={"channelId": channel_id, "page": page, "perPage": 28, "sort": "ForYou"},
            timeout=15,
        )
        if res.status_code == 200:
            return res.json().get("data", {"items": [], "next_page": None})
    except Exception:
        pass
    return {"items": [], "next_page": None}

@app.get("/v1/search")
def get_search(q: str = Query(...), page: int = 1, _ = Depends(verify_token)):
    try:
        token = get_guest_token()
        headers = {}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        res = session.post(
            f"{H5_API_BASE}/subject/search",
            json={"keyword": q, "page": page, "perPage": 28, "subjectType": 0},
            headers=headers,
            timeout=15,
        )
        if res.status_code == 200:
            return res.json().get("data", {"items": [], "next_page": None})
    except Exception:
        pass
    return {"items": [], "next_page": None}

@app.get("/v1/search/suggestions")
def get_suggestions(q: str = Query(...), _ = Depends(verify_token)):
    try:
        token = get_guest_token()
        headers = {}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        res = session.post(
            f"{H5_API_BASE}/subject/search-suggest",
            json={"keyword": q, "perPage": 10},
            headers=headers,
            timeout=15,
        )
        if res.status_code == 200:
            items = res.json().get("data", {}).get("items", [])
            return [x["word"] for x in items if x.get("word")]
    except Exception:
        pass
    return []

@app.get("/v1/search/popular")
def get_popular(_ = Depends(verify_token)):
    try:
        res = session.get(
            f"{H5_API_BASE}/subject/everyone-search",
            params={"host": "themoviebox.xyz"},
            timeout=15,
        )
        if res.status_code == 200:
            items = res.json().get("data", {}).get("everyoneSearch", [])
            return [x["title"] for x in items if x.get("title")]
    except Exception:
        pass
    return []

@app.get("/v1/titles/{path:path}/recommendations")
def get_recommendations(path: str, page: int = 1, _ = Depends(verify_token)):
    try:
        headers = {"Referer": f"{UPSTREAM_BASE}/movies/{path}"}
        detail_res = session.get(
            f"{H5_API_BASE}/detail",
            params={"detailPath": path, "host": "themoviebox.xyz"},
            headers=headers,
            timeout=15,
        )
        if detail_res.status_code == 200:
            subject_id = detail_res.json().get("data", {}).get("subject", {}).get("subjectId")
            if subject_id:
                rec_res = session.get(
                    f"{H5_API_BASE}/subject/detail-rec",
                    params={"subjectId": subject_id, "page": page, "perPage": 12, "host": "themoviebox.xyz"},
                    headers=headers,
                    timeout=15,
                )
                if rec_res.status_code == 200:
                    items = rec_res.json().get("data", {}).get("items", [])
                    return {"items": items, "next_page": page + 1 if len(items) == 12 else None}
    except Exception:
        pass
    return {"items": [], "next_page": None}

@app.get("/v1/titles/{path:path}/playback")
def get_playback(path: str, season: int = 0, episode: int = 0, _ = Depends(verify_token)):
    try:
        headers = {"Referer": f"{UPSTREAM_BASE}/movies/{path}"}
        detail_res = session.get(
            f"{H5_API_BASE}/detail",
            params={"detailPath": path, "host": "themoviebox.xyz"},
            headers=headers,
            timeout=15,
        )
        subject_id = None
        if detail_res.status_code == 200:
            subject_data = detail_res.json().get("data", {})
            subject_id = subject_data.get("subject", {}).get("subjectId")

        play_res = session.get(
            f"{H5_API_BASE}/subject/play",
            params={
                "subjectId": subject_id or "",
                "se": season,
                "ep": episode,
                "detailPath": path,
                "streamSignType": 1,
                "supportCodecs[h264]": 1,
            },
            headers=headers,
            timeout=15,
        )
        if play_res.status_code == 200:
            return play_res.json().get("data", {"streams": [], "vip_locked": False, "limited": False})
        raise HTTPException(status_code=play_res.status_code, detail="Playback unavailable")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/v1/titles/{path:path}/captions")
def get_captions(path: str, stream_id: str = "", season: int = 0, episode: int = 0, _ = Depends(verify_token)):
    try:
        headers = {"Referer": f"{UPSTREAM_BASE}/movies/{path}"}
        detail_res = session.get(
            f"{H5_API_BASE}/detail",
            params={"detailPath": path, "host": "themoviebox.xyz"},
            headers=headers,
            timeout=15,
        )
        subject_id = ""
        if detail_res.status_code == 200:
            subject_id = detail_res.json().get("data", {}).get("subject", {}).get("subjectId", "")

        cap_res = session.get(
            f"{H5_API_BASE}/subject/caption",
            params={
                "format": "MP4",
                "id": stream_id,
                "subjectId": subject_id,
                "detailPath": path,
            },
            headers=headers,
            timeout=15,
        )
        if cap_res.status_code == 200:
            captions_raw = cap_res.json().get("data", {}).get("captions", [])
            formatted = []
            for c in captions_raw:
                lang = c.get("lan", "en").replace("in_id", "id")
                formatted.append({
                    "label": c.get("lanName", lang),
                    "language": lang,
                    "url": c.get("url"),
                    "request_headers": {"Referer": UPSTREAM_BASE, "User-Agent": DEFAULT_HEADERS["User-Agent"]}
                })
            return formatted
    except Exception:
        pass
    return []

@app.get("/v1/titles/{path:path}")
def get_title_detail(path: str, _ = Depends(verify_token)):
    try:
        headers = {"Referer": f"{UPSTREAM_BASE}/movies/{path}"}
        res = session.get(
            f"{H5_API_BASE}/detail",
            params={"detailPath": path, "host": "themoviebox.xyz"},
            headers=headers,
            timeout=15,
        )
        if res.status_code == 200:
            payload = res.json()
            data = payload.get("data")
            if data and ("subject" in data or "title" in data):
                return data
            if payload.get("code") == 0:
                return data or {}
            raise HTTPException(status_code=404, detail=f"Upstream returned code {payload.get('code')}: {payload.get('msg')}")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    raise HTTPException(status_code=404, detail="Title not found")
