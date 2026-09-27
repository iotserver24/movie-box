from typing import Literal

from pydantic import BaseModel, Field


class Title(BaseModel):
    id: str
    detail_path: str
    kind: str
    title: str
    description: str = ""
    release_date: str | None = None
    duration_seconds: int | None = None
    genres: list[str] = Field(default_factory=list)
    poster_url: str | None = None
    backdrop_url: str | None = None
    country: str | None = None
    rating: str | None = None
    has_resource: bool = False


class Page(BaseModel):
    items: list[Title]
    page: int = 1
    next_page: int | None = None
    has_more: bool = False


class Section(BaseModel):
    title: str
    kind: str
    items: list[Title]


class Home(BaseModel):
    banners: list[Title]
    sections: list[Section]


class FilterValue(BaseModel):
    id: str
    label: str


class FilterGroup(BaseModel):
    key: str
    label: str
    values: list[FilterValue]


class CatalogFilters(BaseModel):
    groups: list[FilterGroup]


class Ranking(BaseModel):
    id: str
    name: str


class Season(BaseModel):
    number: int
    episode_count: int
    resolutions: list[int]


class Episode(BaseModel):
    season: int
    number: int


class Dub(BaseModel):
    id: str
    detail_path: str
    language: str
    label: str
    original: bool


class Detail(BaseModel):
    title: Title
    cast: list[dict] = Field(default_factory=list)
    seasons: list[Season] = Field(default_factory=list)
    dubs: list[Dub] = Field(default_factory=list)
    trailer_url: str | None = None


class Stream(BaseModel):
    id: str
    format: str
    resolutions: str
    codec: str | None = None
    size_bytes: int | None = None
    duration_seconds: int | None = None
    url: str
    request_headers: dict[str, str] = Field(default_factory=dict)
    vip_locked: bool = False


class Playback(BaseModel):
    title_id: str
    season: int
    episode: int
    streams: list[Stream]
    limited: bool = False
    vip_locked: bool = False
    max_resolution: int | None = None


class Caption(BaseModel):
    language: str
    label: str
    format: str
    url: str
    size_bytes: int | None = None
    delay_ms: int = 0
    request_headers: dict[str, str] = Field(default_factory=dict)


class Health(BaseModel):
    status: Literal["ok"] = "ok"
