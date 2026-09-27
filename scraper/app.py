import os
import secrets
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.responses import JSONResponse

from .models import Caption, CatalogFilters, Detail, Episode, Health, Home, Page, Playback, Ranking
from .provider import MovieBoxProvider, ProviderError


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    app.state.provider.close()


app = FastAPI(title="MovieBox scraper", version="1.0.0", lifespan=lifespan)
app.state.provider = MovieBoxProvider()


def provider(request: Request, authorization: Annotated[str | None, Header()] = None) -> MovieBoxProvider:
    token = os.getenv("SCRAPER_API_TOKEN", "")
    if token and not secrets.compare_digest(authorization or "", f"Bearer {token}"):
        raise HTTPException(status_code=401, detail="Invalid API token")
    return request.app.state.provider


@app.exception_handler(ProviderError)
async def provider_error(_request: Request, error: ProviderError):
    return JSONResponse(status_code=error.status, content={"detail": str(error)})


@app.get("/health", response_model=Health)
def health():
    return Health()


@app.get("/v1/home", response_model=Home)
def home(source: Annotated[MovieBoxProvider, Depends(provider)]):
    return source.home()


@app.get("/v1/collections/{name}", response_model=Home)
def collection(name: str, source: Annotated[MovieBoxProvider, Depends(provider)]):
    return source.collection(name)


@app.get("/v1/browse", response_model=Page)
def browse(source: Annotated[MovieBoxProvider, Depends(provider)], page: Annotated[int, Query(ge=1)] = 1, kind: str | None = None, tab: str | None = None):
    if kind not in (None, "movie", "series", "short_series", "other"):
        raise HTTPException(status_code=422, detail="Invalid kind")
    if tab not in (None, "home", "movies", "midnight"):
        raise HTTPException(status_code=422, detail="Invalid tab")
    return source.browse(page, kind, tab)


@app.get("/v1/catalog/{name}/filters", response_model=CatalogFilters)
def catalog_filters(name: str, source: Annotated[MovieBoxProvider, Depends(provider)]):
    return source.catalog_filters(name)


@app.get("/v1/catalog/{name}", response_model=Page)
def catalog(name: str, source: Annotated[MovieBoxProvider, Depends(provider)], page: Annotated[int, Query(ge=1)] = 1, genre: Annotated[str | None, Query(max_length=80)] = None, country: Annotated[str | None, Query(max_length=80)] = None, year: Annotated[str | None, Query(max_length=10)] = None, language: Annotated[str | None, Query(max_length=80)] = None, sort: Annotated[str | None, Query(max_length=40)] = None):
    return source.catalog(name, page, genre=genre, country=country, year=year, language=language, sort=sort)


@app.get("/v1/rankings", response_model=list[Ranking])
def rankings(source: Annotated[MovieBoxProvider, Depends(provider)]):
    return source.rankings()


@app.get("/v1/rankings/{ranking_id}", response_model=Page)
def ranking(ranking_id: str, source: Annotated[MovieBoxProvider, Depends(provider)], page: Annotated[int, Query(ge=1)] = 1):
    return source.ranking(ranking_id, page)


@app.get("/v1/search", response_model=Page)
def search(source: Annotated[MovieBoxProvider, Depends(provider)], q: Annotated[str, Query(min_length=1, max_length=100)], page: Annotated[int, Query(ge=1)] = 1):
    return source.search(q.strip(), page)


@app.get("/v1/search/suggestions", response_model=list[str])
def suggestions(source: Annotated[MovieBoxProvider, Depends(provider)], q: Annotated[str, Query(min_length=1, max_length=100)]):
    return source.suggestions(q.strip())


@app.get("/v1/search/popular", response_model=list[str])
def popular_searches(source: Annotated[MovieBoxProvider, Depends(provider)]):
    return source.popular_searches()


@app.get("/v1/titles/{detail_path}", response_model=Detail)
def detail(detail_path: str, source: Annotated[MovieBoxProvider, Depends(provider)]):
    return source.detail(detail_path)


@app.get("/v1/titles/{detail_path}/episodes", response_model=list[Episode])
def episodes(detail_path: str, source: Annotated[MovieBoxProvider, Depends(provider)], season: Annotated[int, Query(ge=1)]):
    return source.episodes(detail_path, season)


@app.get("/v1/titles/{detail_path}/recommendations", response_model=Page)
def recommendations(detail_path: str, source: Annotated[MovieBoxProvider, Depends(provider)], page: Annotated[int, Query(ge=1)] = 1):
    return source.recommendations(detail_path, page)


@app.get("/v1/titles/{detail_path}/playback", response_model=Playback)
def playback(detail_path: str, source: Annotated[MovieBoxProvider, Depends(provider)], season: Annotated[int, Query(ge=0)] = 0, episode: Annotated[int, Query(ge=0)] = 0):
    return source.playback(detail_path, season, episode)


@app.get("/v1/titles/{detail_path}/captions", response_model=list[Caption])
def captions(detail_path: str, source: Annotated[MovieBoxProvider, Depends(provider)], stream_id: str, season: Annotated[int, Query(ge=0)] = 0, episode: Annotated[int, Query(ge=0)] = 0):
    return source.captions(detail_path, stream_id, season, episode)
