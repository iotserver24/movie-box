"""Keep bundled app notices identical to the canonical repository files."""

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "movie_box_app" / "assets" / "notices"
NAMES = ("LICENSE", "CREDITS.md")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Report stale notices without writing")
    args = parser.parse_args()
    stale = []
    for name in NAMES:
        source = (ROOT / name).read_bytes()
        target = DESTINATION / name
        if target.is_file() and target.read_bytes() == source:
            continue
        stale.append(name)
        if not args.check:
            DESTINATION.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source)
    if args.check and stale:
        parser.exit(1, "Bundled notices are missing or stale: " + ", ".join(stale) + "\n")
    print("Bundled notices match LICENSE and CREDITS.md.")


if __name__ == "__main__":
    main()
