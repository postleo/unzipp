<p align="center">
  <img src="assets/unzipp.png" alt="unzipp" width="360">
</p>

<h1 align="center">unzipp</h1>

A small, dependency-free GitHub Action that finds and extracts `.zip` archives
anywhere in your repository — on any branch, including `main` — and can
optionally commit the extracted contents back to the branch.

- 🔍 Find archives with a glob pattern (recursive by default)
- 📂 Extract next to each archive or collect everything under one folder
- ♻️ Optionally delete the source `.zip` after extraction
- ✅ Optionally commit & push the extracted files back to the branch
- 🧩 Composite action — no Docker, no `node_modules`, fast cold start

---

## Quickstart — already have `.zip` files in your repo?

Extract everything in one run, with no local tooling:

**1.** Add this file to your repo as `.github/workflows/unzip.yml`:

```yaml
name: Unzip Archives

on:
  workflow_dispatch:        # run on demand from the Actions tab

permissions:
  contents: write           # lets the action commit the extracted files back

jobs:
  unzip:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: postleo/unzipp@v1
        with:
          pattern: "**/*.zip"
          delete-zip: "true"
          commit: "true"
```

**2.** Commit and push it.

**3.** Open the **Actions** tab → **Unzip Archives** → **Run workflow** → pick your
branch → **Run workflow**.

unzipp scans the whole repo, extracts each `archive.zip` into an `archive/`
folder next to it, deletes the original `.zip`, and commits the result back to
your branch. A ready-to-copy version ships in
[`.github/workflows/example-unzip.yml`](.github/workflows/example-unzip.yml).

> **Want it fully automatic instead?** Swap the trigger so it runs every time a
> `.zip` is pushed to any branch — no manual step:
>
> ```yaml
> on:
>   push:
>     paths: ["**/*.zip"]
> ```

---

## Usage

```yaml
- uses: actions/checkout@v4

- name: Unzip archives
  uses: postleo/unzipp@v1
  with:
    path: "."
    pattern: "**/*.zip"
```

### Extract and commit back to the branch

Give the workflow `contents: write` permission so the action can push the
extracted files back.

```yaml
permissions:
  contents: write

jobs:
  unzip:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: postleo/unzipp@v1
        with:
          pattern: "**/*.zip"
          delete-zip: "true"
          commit: "true"
          commit-message: "chore: unzip archives [skip ci]"
```

### Run automatically when a zip is added to any branch

```yaml
on:
  push:
    paths:
      - "**/*.zip"
```

A full, ready-to-copy workflow lives in
[`.github/workflows/example-unzip.yml`](.github/workflows/example-unzip.yml).

---

## Inputs

| Name                | Default                              | Description |
| ------------------- | ------------------------------------ | ----------- |
| `path`              | `.`                                  | Root directory to search for `.zip` files. |
| `pattern`           | `**/*.zip`                           | Glob (relative to `path`) matching archives. |
| `recursive`         | `true`                               | Search subdirectories. Ignored when `pattern` contains `**`. |
| `destination`       | `alongside`                          | `alongside` extracts next to each zip; otherwise a directory path to collect everything. |
| `flatten`           | `false`                              | Extract directly into the destination instead of a per-archive subfolder. |
| `strip-components`  | `0`                                  | Drop this many leading path components from extracted entries. Use `1` to remove a top-level folder a zip wraps its contents in (like `tar --strip-components`). |
| `overwrite`         | `true`                               | Overwrite existing files when extracting. |
| `delete-zip`        | `false`                              | Delete each `.zip` after successful extraction. |
| `fail-on-empty`     | `false`                              | Fail the step if no archives match. |
| `commit`            | `false`                              | Commit extracted files (and deletions) back to the branch. |
| `commit-message`    | `chore: unzip archives [skip ci]`    | Commit message when `commit` is true. |
| `commit-user-name`  | `github-actions[bot]`                | Git `user.name` for the commit. |
| `commit-user-email` | `github-actions[bot]@users.noreply.github.com` | Git `user.email` for the commit. |

## Outputs

| Name                 | Description |
| -------------------- | ----------- |
| `extracted-count`    | Number of archives extracted. |
| `extracted-archives` | Newline-separated list of extracted `.zip` files. |
| `output-paths`       | Newline-separated list of extraction destinations. |
| `committed`          | `true` if a commit was created, otherwise `false`. |

### Using outputs

```yaml
- id: unzip
  uses: postleo/unzipp@v1
  with:
    pattern: "release/*.zip"

- run: echo "Extracted ${{ steps.unzip.outputs.extracted-count }} archive(s)"
```

---

## Extraction layout

Given `data/archive.zip`:

| Settings                                   | Result |
| ------------------------------------------ | ------ |
| `destination: alongside` (default)         | `data/archive/…` |
| `destination: alongside`, `flatten: true`  | `data/…` |
| `destination: "."`                         | `archive/…` (repository root) |
| `destination: out`                         | `out/archive/…` |
| `destination: out`, `flatten: true`        | `out/…` |

### Dropping folders that are *inside* the zip

`flatten` controls the folder **unzipp** creates. If the archive itself wraps
everything in a top-level folder (e.g. the zip contains `release-v2/app.js`),
use `strip-components` to remove it:

| Archive contains          | `strip-components: 0` (default) | `strip-components: 1` |
| ------------------------- | ------------------------------- | --------------------- |
| `release-v2/app.js`       | `…/release-v2/app.js`           | `…/app.js`            |

Combine `destination: "."`, `flatten: true`, and `strip-components: 1` to drop
a zip's contents straight into the repository root.

---

## Interactive example workflow

[`.github/workflows/example-unzip.yml`](.github/workflows/example-unzip.yml) is a
ready-to-copy `workflow_dispatch` workflow. When you click **Run workflow** it
prompts for:

- **pattern** — which archives to extract
- **destination** — `alongside`, `.` (repo root), or a folder name
- **flatten** — put contents straight into the destination (no per-zip folder)
- **strip_top_level_folder** — drop a wrapper folder that lives inside the zip
- **delete_zip** — remove each `.zip` after extraction
- **target_branch** — which branch to commit the results to (blank = current)
- **create_branch** — create that branch if it doesn't exist yet

---

## Notes

- Runs on Linux and macOS runners (relies on the `unzip` CLI, preinstalled on
  GitHub-hosted `ubuntu-*` and `macos-*` images).
- When `commit: true`, the workflow must use `actions/checkout` and have
  `permissions: contents: write`. The default `GITHUB_TOKEN` is sufficient for
  pushing to the same repository.
- Add `[skip ci]` to the commit message (the default already does) to avoid
  triggering another workflow run from the commit the action makes.

## License

[MIT](LICENSE)
