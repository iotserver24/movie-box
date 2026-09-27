import time
from pathlib import Path

import requests

page = "https://themoviebox.xyz/movies/masters-of-the-universe-g6fDdvegRi9"
base = "Masters of the Universe"
headers = {"Referer": page, "User-Agent": "Mozilla/5.0"}
session = requests.Session()

print("Fetching playback details...", flush=True)
play = session.get(
    "https://themoviebox.xyz/wefeed-h5api-bff/subject/play",
    params={
        "subjectId": "7808991045882365944",
        "se": 0,
        "ep": 0,
        "detailPath": "masters-of-the-universe-g6fDdvegRi9",
        "streamSignType": 1,
        "supportCodecs[h264]": 1,
    },
    headers=headers,
    timeout=30,
)
play.raise_for_status()
stream = next(
    s for s in play.json()["data"]["streams"]
    if s["format"] == "MP4" and s["resolutions"] == "1080"
)

path = Path(f"{base}.mp4")
total = int(stream["size"])
existing = path.stat().st_size if path.exists() else 0
if existing > total:
    raise RuntimeError(f"Existing file is larger than the expected {total} bytes: {path}")
print(f"1080p MP4: {total / 1_000_000_000:.2f} GB | Already saved: {existing / 1_000_000_000:.2f} GB", flush=True)

if existing < total:
    video_headers = {**headers, "Origin": "https://themoviebox.xyz"}
    if existing:
        video_headers["Range"] = f"bytes={existing}-"
        print("Resuming partial download...", flush=True)
    else:
        print("Starting download...", flush=True)

    with session.get(stream["url"], headers=video_headers, stream=True, timeout=60) as video:
        video.raise_for_status()
        if existing:
            expected_range = f"bytes {existing}-"
            if video.status_code != 206 or not video.headers.get("Content-Range", "").startswith(expected_range):
                raise RuntimeError("Server did not honor the resume range; existing file was left unchanged")
        elif video.status_code not in (200, 206):
            raise RuntimeError(f"Unexpected video response: {video.status_code}")

        saved = existing
        start_time = time.monotonic()
        last_time = start_time
        last_saved = saved
        with path.open("ab" if existing else "wb") as output:
            for chunk in video.iter_content(chunk_size=1024 * 1024):
                if not chunk:
                    continue
                output.write(chunk)
                saved += len(chunk)
                now = time.monotonic()
                elapsed = now - last_time
                if elapsed >= 1 or saved >= total:
                    speed = (saved - last_saved) / elapsed if elapsed else 0
                    remaining = int((total - saved) / speed) if speed else 0
                    eta = f"{remaining // 3600:02}:{remaining // 60 % 60:02}:{remaining % 60:02}"
                    spent = int(now - start_time)
                    elapsed_text = f"{spent // 3600:02}:{spent // 60 % 60:02}:{spent % 60:02}"
                    print(
                        f"\r{saved / total:5.1%} | {saved / 1_000_000_000:.2f}/{total / 1_000_000_000:.2f} GB"
                        f" | {speed / 1_000_000:.2f} MB/s | Elapsed {elapsed_text} | ETA {eta}   ",
                        end="", flush=True,
                    )
                    last_time, last_saved = now, saved
    print()
    if saved != total:
        raise RuntimeError(f"Download ended early: {saved} of {total} bytes saved")
print(f"Video saved: {path}", flush=True)

print("Fetching subtitle details...", flush=True)
captions = session.get(
    "https://h5-api.aoneroom.com/wefeed-h5api-bff/subject/caption",
    params={
        "format": "MP4",
        "id": stream["id"],
        "subjectId": "7808991045882365944",
        "detailPath": "masters-of-the-universe-g6fDdvegRi9",
    },
    headers=headers,
    timeout=30,
)
captions.raise_for_status()
for caption in captions.json()["data"]["captions"]:
    language = caption["lan"].replace("in_id", "id")
    subtitle_path = Path(f"{base}.{language}.srt")
    if subtitle_path.exists() and subtitle_path.stat().st_size == int(caption["size"]):
        print(f"Subtitle already saved: {caption['lanName']}", flush=True)
        continue
    response = session.get(caption["url"], headers=headers, timeout=30)
    response.raise_for_status()
    subtitle_path.write_bytes(response.content)
    print(f"Subtitle saved: {caption['lanName']} ({len(response.content)} bytes)", flush=True)
