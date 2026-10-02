import hashlib
import unittest

from scripts.verify_apk_certificate import verify


class ApkCertificateTests(unittest.TestCase):
    certificate = b"test signing certificate"
    digest = hashlib.sha256(certificate).hexdigest()

    def report(self, *labels):
        return "Number of signers: 1\n" + "\n".join(
            f"{label} certificate SHA-256 digest: {self.digest}" for label in labels
        ) + "\n"

    def test_legacy_output(self):
        verify(self.report("Signer #1"), self.certificate)

    def test_build_tools_37_output(self):
        verify(self.report("V2 Signer:"), self.certificate)

    def test_multiple_schemes_for_same_certificate(self):
        verify(self.report("V1 Signer:", "V2 Signer:", "V3.1 Signer:"), self.certificate)

    def test_uppercase_digest(self):
        verify(self.report("V2 Signer:").replace(self.digest, self.digest.upper()), self.certificate)

    def test_mismatched_certificate(self):
        with self.assertRaisesRegex(ValueError, "does not match"):
            verify(self.report("V2 Signer:"), b"another certificate")

    def test_different_certificate_in_another_scheme(self):
        report = self.report("V2 Signer:") + f"V3 Signer: certificate SHA-256 digest: {'a' * 64}\n"
        with self.assertRaisesRegex(ValueError, "does not match"):
            verify(report, self.certificate)

    def test_missing_or_malformed_certificate(self):
        for report in ("Number of signers: 1\n", self.report("Unknown Signer:"),
                       self.report("V2 Signer:").replace(self.digest, "invalid"),
                       self.report("V2 Signer:").replace("certificate", "public key")):
            with self.subTest(report=report), self.assertRaisesRegex(ValueError, "No signing certificate"):
                verify(report, self.certificate)

    def test_reject_multiple_or_missing_signer_count(self):
        for count in ("0", "2", ""):
            with self.subTest(count=count), self.assertRaisesRegex(ValueError, "exactly one"):
                verify(self.report("Signer #1").replace("signers: 1", f"signers: {count}"), self.certificate)


if __name__ == "__main__":
    unittest.main()
