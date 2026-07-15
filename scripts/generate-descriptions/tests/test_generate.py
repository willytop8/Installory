from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


GENERATOR_PATH = Path(__file__).resolve().parents[1] / "generate.py"
SPEC = importlib.util.spec_from_file_location("installory_description_generator", GENERATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
generate = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = generate
SPEC.loader.exec_module(generate)


def descriptions_for(**counts: int) -> dict[str, str]:
    descriptions: dict[str, str] = {}
    for manager, count in counts.items():
        for index in range(count):
            descriptions[f"{manager}:package-{index}"] = f"Description {index}"
    return descriptions


class PartialModeSafetyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.production = self.root / "descriptions.json"
        self.production.write_bytes(b"last-good-production")

    def fetch_mocks(self):
        return (
            mock.patch.object(
                generate,
                "fetch_homebrew",
                return_value=descriptions_for(brew=1, brewCask=1),
            ),
            mock.patch.object(
                generate,
                "fetch_pypi",
                return_value=descriptions_for(pip=1),
            ),
            mock.patch.object(
                generate,
                "fetch_npm",
                return_value=descriptions_for(npm=1),
            ),
        )

    def test_limit_cannot_overwrite_production_by_default(self) -> None:
        original = self.production.read_bytes()
        with mock.patch.object(generate, "OUTPUT", self.production), mock.patch.object(
            generate, "fetch_homebrew"
        ) as fetch_homebrew:
            with self.assertRaises(SystemExit) as raised:
                generate.main(["--limit", "1"])

        self.assertEqual(raised.exception.code, 2)
        fetch_homebrew.assert_not_called()
        self.assertEqual(self.production.read_bytes(), original)

    def test_skipped_registry_cannot_overwrite_production_by_default(self) -> None:
        original = self.production.read_bytes()
        with mock.patch.object(generate, "OUTPUT", self.production), mock.patch.object(
            generate, "fetch_homebrew"
        ) as fetch_homebrew:
            with self.assertRaises(SystemExit):
                generate.main(["--no-npm"])

        fetch_homebrew.assert_not_called()
        self.assertEqual(self.production.read_bytes(), original)

    def test_partial_run_can_write_to_explicit_scratch_output(self) -> None:
        scratch = self.root / "partial.json"
        original = self.production.read_bytes()
        homebrew, pypi, npm = self.fetch_mocks()
        with mock.patch.object(generate, "OUTPUT", self.production), homebrew, pypi, npm:
            status = generate.main(["--limit", "1", "--output", str(scratch)])

        self.assertEqual(status, 0)
        self.assertEqual(self.production.read_bytes(), original)
        corpus = generate.load_corpus(scratch)
        self.assertEqual(
            corpus["counts"],
            {"brew": 1, "brewCask": 1, "pip": 1, "npm": 1},
        )

    def test_check_mode_never_writes(self) -> None:
        original = self.production.read_bytes()
        homebrew, pypi, npm = self.fetch_mocks()
        with mock.patch.object(generate, "OUTPUT", self.production), homebrew, pypi, npm:
            status = generate.main(["--limit", "1", "--check"])

        self.assertEqual(status, 0)
        self.assertEqual(self.production.read_bytes(), original)

    def test_allow_partial_is_an_explicit_production_override(self) -> None:
        homebrew, _, _ = self.fetch_mocks()
        with mock.patch.object(generate, "OUTPUT", self.production), homebrew:
            status = generate.main(["--no-pip", "--no-npm", "--allow-partial"])

        self.assertEqual(status, 0)
        corpus = generate.load_corpus(self.production)
        self.assertEqual(
            corpus["counts"],
            {"brew": 1, "brewCask": 1, "pip": 0, "npm": 0},
        )


class CorpusValidationTests(unittest.TestCase):
    def test_declared_counts_must_match_description_keys(self) -> None:
        corpus = generate.build_corpus(
            descriptions_for(brew=1, brewCask=1, pip=1, npm=1),
            generated="2026-07-15T12:00:00+00:00",
        )
        corpus["counts"]["pip"] = 2

        with self.assertRaisesRegex(generate.CorpusValidationError, "do not match"):
            generate.validate_corpus(corpus)

    def test_unknown_or_noncanonical_keys_are_rejected(self) -> None:
        corpus = {
            "generated": "2026-07-15T12:00:00+00:00",
            "counts": {"brew": 0, "brewCask": 0, "pip": 1, "npm": 0},
            "descriptions": {"pip:Some_Package": "Description"},
        }

        with self.assertRaisesRegex(generate.CorpusValidationError, "PEP 503"):
            generate.validate_corpus(corpus)

    def test_atomic_write_produces_count_consistent_json(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "descriptions.json"
            corpus = generate.build_corpus(
                descriptions_for(brew=2, brewCask=1, pip=3, npm=4),
                generated="2026-07-15T12:00:00+00:00",
            )

            generate.write_corpus_atomic(corpus, output)

            parsed = json.loads(output.read_text(encoding="utf-8"))
            generate.validate_corpus(parsed)
            self.assertEqual(sum(parsed["counts"].values()), len(parsed["descriptions"]))
            self.assertEqual(list(output.parent.glob(f".{output.name}.*.tmp")), [])

    def test_failed_atomic_replace_preserves_last_good_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "descriptions.json"
            output.write_bytes(b"last-good")
            corpus = generate.build_corpus(
                descriptions_for(brew=1, brewCask=1, pip=1, npm=1)
            )

            with mock.patch.object(generate.os, "replace", side_effect=OSError("disk full")):
                with self.assertRaisesRegex(OSError, "disk full"):
                    generate.write_corpus_atomic(corpus, output)

            self.assertEqual(output.read_bytes(), b"last-good")
            self.assertEqual(list(output.parent.glob(f".{output.name}.*.tmp")), [])

    def test_invalid_corpus_never_reaches_atomic_replace(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "descriptions.json"
            output.write_bytes(b"last-good")
            corpus = generate.build_corpus(
                descriptions_for(brew=1, brewCask=1, pip=1, npm=1)
            )
            corpus["counts"]["npm"] = 99

            with mock.patch.object(generate.os, "replace") as replace:
                with self.assertRaises(generate.CorpusValidationError):
                    generate.write_corpus_atomic(corpus, output)

            replace.assert_not_called()
            self.assertEqual(output.read_bytes(), b"last-good")


class LastGoodProductionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.production = Path(self.temporary_directory.name) / "descriptions.json"
        self.last_good = generate.build_corpus(
            descriptions_for(brew=5, brewCask=5, pip=5, npm=5),
            generated="2026-07-14T12:00:00+00:00",
        )
        generate.write_corpus_atomic(self.last_good, self.production)

    def test_failed_registry_cannot_replace_last_good_corpus(self) -> None:
        original = self.production.read_bytes()
        minimums = {manager: 1 for manager in generate.MANAGER_PREFIXES}

        with mock.patch.object(generate, "OUTPUT", self.production), mock.patch.object(
            generate, "PRODUCTION_MIN_COUNTS", minimums
        ), mock.patch.object(
            generate,
            "fetch_homebrew",
            return_value=descriptions_for(brew=5, brewCask=5),
        ), mock.patch.object(
            generate, "fetch_pypi", return_value={}
        ), mock.patch.object(
            generate, "fetch_npm", return_value=descriptions_for(npm=5)
        ):
            status = generate.main([])

        self.assertEqual(status, 1)
        self.assertEqual(self.production.read_bytes(), original)

    def test_full_write_must_retain_reasonable_fraction_of_last_good_counts(self) -> None:
        replacement = generate.build_corpus(
            descriptions_for(brew=5, brewCask=5, pip=3, npm=5)
        )
        minimums = {manager: 0 for manager in generate.MANAGER_PREFIXES}

        with mock.patch.object(generate, "PRODUCTION_MIN_COUNTS", minimums):
            with self.assertRaisesRegex(generate.CorpusValidationError, "requires at least 4"):
                generate.validate_corpus(
                    replacement,
                    enforce_production_floors=True,
                    last_good_counts=self.last_good["counts"],
                )


if __name__ == "__main__":
    unittest.main()
