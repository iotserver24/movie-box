"""Compare apksigner's certificate report with an exported signing certificate."""

import hashlib
from pathlib import Path
import re
import sys


CERTIFICATE = re.compile(
    r"^(?:Signer #\d+|V\d+(?:\.\d+)? Signer(?: #\d+)?:) "
    r"certificate SHA-256 digest: ([0-9a-fA-F]{64})$",
    re.MULTILINE,
)


def verify(report: str, certificate: bytes) -> None:
    if re.findall(r"^Number of signers: (\d+)$", report, re.MULTILINE) != ["1"]:
        raise ValueError("Release APK must have exactly one signer.")
    digests = {digest.lower() for digest in CERTIFICATE.findall(report)}
    if not digests:
        raise ValueError("No signing certificate SHA-256 digest found in apksigner output.")
    expected = hashlib.sha256(certificate).hexdigest()
    if digests != {expected}:
        raise ValueError("APK signing certificate does not match the release keystore.")


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: verify_apk_certificate.py REPORT CERTIFICATE.der", file=sys.stderr)
        return 2
    try:
        verify(Path(sys.argv[1]).read_text(), Path(sys.argv[2]).read_bytes())
    except (OSError, ValueError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    print("APK signing certificate matches the release keystore.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
