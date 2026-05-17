# Description Sources and Attribution

The `descriptions.json` corpus bundled with Backshelf contains short
one-line package summaries sourced from the following public APIs:

## Homebrew

**Source:** formulae.brew.sh (the official Homebrew formula/cask API)
**Field used:** `desc` (formula) / `desc` (cask)
**License:** Homebrew formula metadata is distributed under the
  [BSD 2-Clause License](https://github.com/Homebrew/homebrew-core/blob/master/LICENSE.txt).

## PyPI

**Source:** pypi.org/pypi/{name}/json (the official PyPI JSON API)
**Field used:** `info.summary`
**License:** Package metadata on PyPI is user-submitted. Descriptions are
  typically under each package's own license. The PyPI service itself is
  provided by the Python Software Foundation.

## npm

**Source:** registry.npmjs.org/{name}/latest (the official npm registry API)
**Field used:** `description`
**License:** Package metadata on npm is user-submitted. Descriptions are
  typically under each package's own license. The npm registry is operated
  by npm, Inc.

---

Backshelf uses only the short summary/description field from each registry —
no README content, no source code. All descriptions are one-line factual
summaries of what a package does. This use is consistent with the public
nature of package registries, whose purpose is precisely to make package
metadata discoverable.
