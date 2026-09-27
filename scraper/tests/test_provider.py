import json

import httpx
import pytest
from fastapi.testclient import TestClient

from scraper.app import app, provider
from scraper.provider import MovieBoxProvider, ProviderError

SUBJECT = {
    "subjectId": "123", "subjectType": 1, "title": "Example Movie",
    "detailPath": "example-movie-abc", "cover": {"url": "https://example.test/poster.jpg"},
    "genre": "Action, Adventure", "hasResource": True,
}
SERIES = {**SUBJECT, "subjectId": "456", "subjectType": 2, "title": "Example Series", "detailPath": "example-series-xyz"}


def source(responses):
    def handler(request):
        key = (request.method, request.url.path)
        value = responses[key]
        if callable(value):
            value = value(request)
        return httpx.Response(200, json={"code": 0, "data": value})
    return MovieBoxProvider(httpx.Client(base_url="https://themoviebox.xyz", transport=httpx.MockTransport(handler)))


def test_home_and_paginated_browse():
    service = source({
        ("GET", "/wefeed-h5api-bff/home"): {"operatingList": [
            {"type": "BANNER", "banner": {"items": [{"subject": SUBJECT}]}},
            {"type": "SUBJECTS_MOVIE", "title": "Movies", "subjects": [SUBJECT, SERIES]},
        ]},
        ("GET", "/wefeed-h5api-bff/tab-operating"): {"operatingList": [{"type": "SUBJECTS_MOVIE", "title": "Movie picks", "subjects": [SUBJECT]}]},
        ("GET", "/wefeed-h5api-bff/subject/everyone-search"): {"everyoneSearch": [{"title": "Example Movie"}]},
        ("POST", "/wefeed-h5api-bff/subject/search-suggest"): {"items": [{"word": "Example Movie"}]},
        ("GET", "/wefeed-h5api-bff/subject/trending"): {
            "subjectList": [SUBJECT, SERIES], "pager": {"hasMore": True, "nextPage": "2"}
        },
    })
    assert service.home().banners[0].poster_url.endswith("poster.jpg")
    assert [x.kind for x in service.home().sections[0].items] == ["movie", "series"]
    assert service.collection("movies").sections[0].items[0].id == "123"
    with pytest.raises(ProviderError):
        service.collection("unknown")
    result = service.browse(1, "series")
    assert [x.id for x in result.items] == ["456"]
    assert result.next_page == 2
    assert service.browse(1, "movie").items[0].kind == "movie"
    assert service.suggestions("Example") == ["Example Movie"]
    assert service.popular_searches() == ["Example Movie"]


def test_search_server_rendered_data():
    import scraper.provider as module
    values = [None, {"pager": 2, "items": 3}, {"hasMore": 5}, [4], {"subjectId": 6, "subjectType": 7, "title": 8, "detailPath": 9}, True, "123", 1, "Example Movie", "example-movie-abc"]
    html = f'<script type="application/json" id="__NUXT_DATA__">{json.dumps(values)}</script>'
    items, found = module._nuxt_search(html)
    assert found and items[0]["subjectId"] == "123"
    assert module._title(items[0]).title == "Example Movie"
    with pytest.raises(ProviderError):
        module._nuxt_search("no data")


def test_paginated_search_with_anonymous_session():
    calls = []

    def handler(request):
        calls.append(request)
        if request.url.path.endswith("/subject/trending"):
            return httpx.Response(200, headers={"x-user": json.dumps({"token": "guest-token"})}, json={"code": 0, "data": {}})
        assert request.headers["authorization"] == "Bearer guest-token"
        assert json.loads(request.content)["page"] == 2
        return httpx.Response(200, json={"code": 0, "data": {"items": [SUBJECT], "pager": {"hasMore": True, "nextPage": "3"}}})

    service = MovieBoxProvider(httpx.Client(base_url="https://themoviebox.xyz", transport=httpx.MockTransport(handler)))
    result = service.search("Example", 2)
    assert result.items[0].id == "123" and result.next_page == 3
    assert len(calls) == 2
    assert service.search("Example", 2) is result


def test_search_fallback_when_anonymous_session_is_unavailable():
    values = [None, {"pager": 2, "items": 3}, {"hasMore": 4}, [5], False, {"subjectId": 6, "subjectType": 7, "title": 8, "detailPath": 9}, "123", 1, "Example Movie", "example-movie-abc"]
    html = f'<script id="__NUXT_DATA__">{json.dumps(values)}</script>'
    calls = []

    def handler(request):
        calls.append(request.url.path)
        if request.url.path.endswith("/subject/trending"):
            return httpx.Response(200, json={"code": 0, "data": {}})
        if request.url.path == "/newWeb/searchResult":
            return httpx.Response(200, text=html)
        raise AssertionError(request.url)

    service = MovieBoxProvider(httpx.Client(base_url="https://themoviebox.xyz", transport=httpx.MockTransport(handler)))
    result = service.search("Example")
    assert result.items[0].id == "123" and not result.has_more
    assert calls == ["/wefeed-h5api-bff/subject/trending"] * 2 + ["/newWeb/searchResult"]
    with pytest.raises(ProviderError):
        service.search("Example", 2)


def test_catalog_and_rankings():
    ranking_values = [None, {"rankingList": 2, "currentId": 4}, [3], {"id": 4, "name": 5}, "rank-1", "Top Movies"]
    ranking_html = f'<script id="__NUXT_DATA__" type="application/json">{json.dumps(ranking_values)}</script>'

    def handler(request):
        if request.url.path == "/ranking-list":
            return httpx.Response(200, text=ranking_html)
        if request.url.path.endswith("/subject/filter"):
            body = json.loads(request.content)
            assert body["channelId"] == 1
            assert body["genre"] == "Action"
            return httpx.Response(200, json={"code": 0, "data": {"items": [SUBJECT], "pager": {"hasMore": True, "nextPage": "2"}}})
        if request.url.path.endswith("/ranking-list/content"):
            assert request.url.params["id"] == "rank-1"
            return httpx.Response(200, json={"code": 0, "data": {"subjectList": [SUBJECT], "pager": {"hasMore": False}}})
        raise AssertionError(request.url)

    service = MovieBoxProvider(httpx.Client(base_url="https://themoviebox.xyz", transport=httpx.MockTransport(handler)))
    assert service.catalog("movies", genre="Action").next_page == 2
    assert service.rankings()[0].name == "Top Movies"
    assert service.ranking("rank-1").items[0].id == "123"
    with pytest.raises(ProviderError):
        service.ranking("not-a-rank")
    with pytest.raises(ProviderError):
        service.catalog("invalid")


def test_detail_playback_captions_and_api_contract():
    def playback(request):
        assert request.url.params["subjectId"] == "123"
        return {"streams": [{"id": "video-1", "format": "MP4", "resolutions": "1080", "url": "https://cdn.test/movie.mp4?sign=secret", "size": "200", "duration": 90}], "dash": [], "hls": [], "playConfig": {"maxResolution": 480}}

    def captions(request):
        assert request.url.params["id"] == "video-1"
        return {"captions": [{"lan": "en", "lanName": "English", "url": "https://cdn.test/movie.srt?sign=secret", "size": "42", "delay": 0}]}

    service = source({
        ("GET", "/wefeed-h5api-bff/detail"): {"subject": SUBJECT, "stars": [], "resource": {"seasons": [{"se": 0, "maxEp": 0, "resolutions": [{"resolution": 1080}]}]}},
        ("GET", "/wefeed-h5api-bff/subject/play"): playback,
        ("GET", "/wefeed-h5api-bff/subject/caption"): captions,
        ("GET", "/wefeed-h5api-bff/subject/detail-rec"): {"items": [SERIES]},
    })
    app.dependency_overrides[provider] = lambda: service
    try:
        with TestClient(app) as client:
            base = "/v1/titles/example-movie-abc"
            assert client.get("/health").json() == {"status": "ok"}
            assert client.get(base).json()["title"]["id"] == "123"
            assert client.get(base + "/recommendations").json()["items"][0]["kind"] == "series"
            stream = client.get(base + "/playback").json()
            assert stream["streams"][0]["format"] == "MP4"
            assert stream["max_resolution"] == 480
            assert client.get(base + "/captions?stream_id=video-1").json()[0]["format"] == "srt"
            assert client.get(base + "/captions?stream_id=unknown").status_code == 404
            assert client.get(base + "/episodes?season=1").status_code == 404
            assert client.get("/v1/browse?page=0").status_code == 422
    finally:
        app.dependency_overrides.clear()
