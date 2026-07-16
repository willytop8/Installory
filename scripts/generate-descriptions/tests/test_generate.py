from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
import urllib.parse
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

    def test_check_mode_never_replaces_output_corpus(self) -> None:
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


class NpmSeedExpansionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)

    @staticmethod
    def response(*names: str, total: int | None = None) -> dict[str, object]:
        return {
            "objects": [{"package": {"name": name}} for name in names],
            "total": len(names) if total is None else total,
        }

    @staticmethod
    def query_parameters(url: str) -> dict[str, list[str]]:
        return urllib.parse.parse_qs(urllib.parse.urlparse(url).query)

    def test_production_queries_are_bounded_real_search_terms(self) -> None:
        queries = generate._NPM_SEARCH_QUERIES

        self.assertGreater(len(queries), 1)
        self.assertEqual(len(queries), len(set(queries)))
        self.assertTrue(all(query.strip() and "*" not in query for query in queries))
        self.assertLessEqual(generate._NPM_SEARCH_PAGE_SIZE, 250)
        self.assertGreater(generate._NPM_SEARCH_MAX_PAGES_PER_QUERY, 0)
        self.assertGreater(generate._NPM_SEARCH_MAX_NEW_NAMES, 0)

    def expand(
        self,
        existing: list[str],
        fetch,
        *,
        seed_file: Path | None = None,
        queries: tuple[str, ...] = ("react",),
        page_size: int = 250,
        max_pages: int = 1,
        max_new_names: int = 100,
    ) -> tuple[list[str], Path]:
        destination = seed_file or self.root / "npm-seed-list.json"
        with mock.patch.object(generate, "fetch_json", side_effect=fetch), mock.patch.object(
            generate, "_NPM_SEARCH_QUERIES", queries
        ), mock.patch.object(
            generate, "_NPM_SEARCH_PAGE_SIZE", page_size
        ), mock.patch.object(
            generate, "_NPM_SEARCH_MAX_PAGES_PER_QUERY", max_pages
        ), mock.patch.object(
            generate, "_NPM_SEARCH_MAX_NEW_NAMES", max_new_names
        ), mock.patch.object(
            generate.time, "sleep"
        ):
            result = generate._try_expand_npm_seed(existing, destination)
        return result, destination

    def test_failed_query_keeps_existing_and_successful_results(self) -> None:
        requested_queries: list[str] = []

        def fetch(url: str) -> dict[str, object]:
            query = self.query_parameters(url)["text"][0]
            requested_queries.append(query)
            if query == "react":
                return self.response("existing", "zeta")
            if query == "broken":
                raise RuntimeError("HTTP 400")
            return self.response("alpha")

        result, seed_file = self.expand(
            ["existing"],
            fetch,
            queries=("react", "broken", "cli"),
        )

        self.assertEqual(requested_queries, ["react", "broken", "cli"])
        self.assertEqual(result, ["existing", "alpha", "zeta"])
        self.assertEqual(json.loads(seed_file.read_text()), result)

    def test_invalid_later_page_keeps_earlier_page(self) -> None:
        offsets: list[int] = []

        def fetch(url: str) -> dict[str, object]:
            offset = int(self.query_parameters(url)["from"][0])
            offsets.append(offset)
            if offset == 0:
                return self.response("beta", "alpha", total=4)
            return {"objects": "not-an-array"}

        result, _ = self.expand(
            ["existing"],
            fetch,
            page_size=2,
            max_pages=2,
        )

        self.assertEqual(offsets, [0, 2])
        self.assertEqual(result, ["existing", "alpha", "beta"])

    def test_names_are_deduplicated_across_existing_seeds_and_queries(self) -> None:
        def fetch(url: str) -> dict[str, object]:
            query = self.query_parameters(url)["text"][0]
            if query == "react":
                return self.response("React", "alpha", "alpha")
            return self.response("react", "beta")

        result, _ = self.expand(
            ["react", "REACT", "seed"],
            fetch,
            queries=("react", "web"),
        )

        self.assertEqual(result, ["react", "seed", "alpha", "beta"])
        self.assertEqual(len(result), len(set(result)))

    def test_pagination_respects_page_size_and_global_new_name_bound(self) -> None:
        requests: list[dict[str, list[str]]] = []

        def fetch(url: str) -> dict[str, object]:
            parameters = self.query_parameters(url)
            requests.append(parameters)
            offset = int(parameters["from"][0])
            return self.response(
                f"package-{offset + 1}",
                f"package-{offset}",
                total=10,
            )

        result, _ = self.expand(
            ["existing"],
            fetch,
            queries=("node",),
            page_size=2,
            max_pages=3,
            max_new_names=3,
        )

        self.assertEqual([int(item["from"][0]) for item in requests], [0, 2])
        self.assertTrue(all(int(item["size"][0]) == 2 for item in requests))
        self.assertEqual(
            result,
            ["existing", "package-0", "package-1", "package-2"],
        )

    def test_result_and_persisted_bytes_are_stable_across_api_ordering(self) -> None:
        first_file = self.root / "first.json"
        second_file = self.root / "second.json"

        first, _ = self.expand(
            ["zeta-seed"],
            lambda _: self.response("beta", "alpha", "beta"),
            seed_file=first_file,
        )
        second, _ = self.expand(
            ["zeta-seed"],
            lambda _: self.response("alpha", "beta"),
            seed_file=second_file,
        )

        self.assertEqual(first, ["zeta-seed", "alpha", "beta"])
        self.assertEqual(second, first)
        self.assertEqual(first_file.read_bytes(), second_file.read_bytes())


if __name__ == "__main__":
    unittest.main()
