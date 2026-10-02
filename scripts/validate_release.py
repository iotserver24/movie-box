import json
import re
import sys
from pathlib import Path

VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", re.ASCII)


def validate(version, build_number, pages, current_version):
    if not VERSION.fullmatch(version) or len(version) > 40:
        raise ValueError("Version must be major.minor.patch without a v prefix or leading zeros.")
    if not re.fullmatch(r"[1-9][0-9]{0,9}", build_number, re.ASCII):
        raise ValueError("Build number must be a positive integer.")
    build = int(build_number)
    if build > 2100000000:
        raise ValueError("Build number exceeds Android's maximum of 2100000000.")
    current_name, current_build = current_version.split("+")
    highest_build = int(current_build)
    highest_version = tuple(map(int, current_name.split(".")))
    for page in pages:
        for release in page:
            tag = release["tag_name"]
            if tag == f"v{version}":
                raise ValueError("This version already has a release or draft; choose a new version.")
            if release.get("draft"):
                continue
            match = VERSION.fullmatch(tag.removeprefix("v"))
            if match:
                highest_version = max(highest_version, tuple(map(int, match.groups())))
            match = re.search(r"^Build number: ([0-9]+)$", release.get("body") or "", re.MULTILINE)
            if match:
                highest_build = max(highest_build, int(match[1]))
    if tuple(map(int, version.split("."))) <= highest_version:
        raise ValueError("Version must be newer than the source version and published releases.")
    if build <= highest_build:
        raise ValueError(f"Build number must exceed {highest_build} to support Android updates.")


def main():
    if len(sys.argv) != 4:
        raise SystemExit("Usage: validate_release.py VERSION BUILD_NUMBER RELEASE_PAGES_JSON")
    version, build_number, releases_file = sys.argv[1:]
    root = Path(__file__).resolve().parents[1]
    pubspec = (root / "movie_box_app/pubspec.yaml").read_text()
    current_version = re.search(r"^version:\s*(\S+)", pubspec, re.MULTILINE).group(1)
    try:
        validate(version, build_number, json.loads(Path(releases_file).read_text()), current_version)
    except ValueError as error:
        raise SystemExit(str(error)) from error
    print(f"Validated release v{version}, Android build {build_number}.")


if __name__ == "__main__":
    main()
