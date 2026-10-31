import os
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

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/v1/home")
def get_home(_ = Depends(verify_token)):
    try:
        res = requests.get(f"{H5_API_BASE}/home", headers={"User-Agent": "Mozilla/5.0"}, timeout=15)
        if res.status_code == 200:
            return res.json().get("data", {"banners": [], "sections": []})
    except Exception:
        pass
    return {"banners": [], "sections": []}

@app.get("/v1/catalog/{name}")
def get_catalog(name: str, page: int = 1, _ = Depends(verify_token)):
    try:
        res = requests.get(
            f"{H5_API_BASE}/catalog/{name}",
            params={"page": page},
            headers={"User-Agent": "Mozilla/5.0"},
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
        res = requests.get(
            f"{H5_API_BASE}/search",
            params={"q": q, "page": page},
            headers={"User-Agent": "Mozilla/5.0"},
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
        res = requests.get(
            f"{H5_API_BASE}/search/suggestions",
            params={"q": q},
            headers={"User-Agent": "Mozilla/5.0"},
            timeout=15,
        )
        if res.status_code == 200:
            return res.json().get("data", [])
    except Exception:
        pass
    return []

@app.get("/v1/search/popular")
def get_popular(_ = Depends(verify_token)):
    try:
        res = requests.get(
            f"{H5_API_BASE}/search/popular",
            headers={"User-Agent": "Mozilla/5.0"},
            timeout=15,
        )
        if res.status_code == 200:
            return res.json().get("data", [])
    except Exception:
        pass
    return []

@app.get("/v1/titles/{path:path}")
def get_title_detail(path: str, _ = Depends(verify_token)):
    try:
        res = requests.get(
            f"{H5_API_BASE}/subject/detail",
            params={"detailPath": path},
            headers={"User-Agent": "Mozilla/5.0", "Referer": f"{UPSTREAM_BASE}/movies/{path}"},
            timeout=15,
        )
        if res.status_code == 200:
            return res.json().get("data", {})
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    raise HTTPException(status_code=404, detail="Title not found")

@app.get("/v1/titles/{path:path}/recommendations")
def get_recommendations(path: str, _ = Depends(verify_token)):
    return {"items": [], "next_page": None}

@app.get("/v1/titles/{path:path}/playback")
def get_playback(path: str, season: int = 0, episode: int = 0, _ = Depends(verify_token)):
    try:
        detail_res = requests.get(
            f"{H5_API_BASE}/subject/detail",
            params={"detailPath": path},
            headers={"User-Agent": "Mozilla/5.0", "Referer": f"{UPSTREAM_BASE}/movies/{path}"},
            timeout=15,
        )
        if detail_res.status_code != 200:
            raise HTTPException(status_code=404, detail="Title not found")

        subject_data = detail_res.json().get("data", {})
        subject_id = subject_data.get("title", {}).get("id")

        play_res = requests.get(
            f"{H5_API_BASE}/subject/play",
            params={
                "subjectId": subject_id,
                "se": season,
                "ep": episode,
                "detailPath": path,
                "streamSignType": 1,
                "supportCodecs[h264]": 1,
            },
            headers={"User-Agent": "Mozilla/5.0", "Referer": f"{UPSTREAM_BASE}/movies/{path}"},
            timeout=15,
        )
        play_res.raise_for_status()
        return play_res.json().get("data", {"streams": [], "vip_locked": False, "limited": False})
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/v1/titles/{path:path}/captions")
def get_captions(path: str, stream_id: str = "", season: int = 0, episode: int = 0, _ = Depends(verify_token)):
    try:
        detail_res = requests.get(
            f"{H5_API_BASE}/subject/detail",
            params={"detailPath": path},
            headers={"User-Agent": "Mozilla/5.0", "Referer": f"{UPSTREAM_BASE}/movies/{path}"},
            timeout=15,
        )
        subject_id = ""
        if detail_res.status_code == 200:
            subject_id = detail_res.json().get("data", {}).get("title", {}).get("id", "")

        cap_res = requests.get(
            "https://h5-api.aoneroom.com/wefeed-h5api-bff/subject/caption",
            params={
                "format": "MP4",
                "id": stream_id,
                "subjectId": subject_id,
                "detailPath": path,
            },
            headers={"User-Agent": "Mozilla/5.0", "Referer": f"{UPSTREAM_BASE}/movies/{path}"},
            timeout=15,
        )
        cap_res.raise_for_status()
        captions_raw = cap_res.json().get("data", {}).get("captions", [])
        formatted = []
        for c in captions_raw:
            lang = c.get("lan", "en").replace("in_id", "id")
            formatted.append({
                "label": c.get("lanName", lang),
                "language": lang,
                "url": c.get("url"),
                "request_headers": {"Referer": UPSTREAM_BASE, "User-Agent": "Mozilla/5.0"}
            })
        return formatted
    except Exception as e:
        return []
