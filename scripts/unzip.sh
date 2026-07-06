#!/usr/bin/env bash
#
# unzip.sh - core logic for the "Unzip Files Action".
#
# Finds .zip archives matching a pattern and extracts them, with options for
# destination, flattening, overwriting, deleting the source archive, and
# committing the results back to the branch.
#
# Configured entirely through INPUT_* environment variables (see action.yml).
# Can also be run locally for testing by exporting those variables.

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

is_true() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    true | 1 | yes | y | on) return 0 ;;
    *) return 1 ;;
  esac
}

log() { printf '%s\n' "$*"; }

group_start() { printf '::group::%s\n' "$*"; }
group_end() { printf '::endgroup::\n'; }

fail() {
  printf '::error::%s\n' "$*"
  exit 1
}

# ---------------------------------------------------------------------------
# Inputs (with defaults so the script is safe to run standalone)
# ---------------------------------------------------------------------------

SEARCH_PATH="${INPUT_PATH:-.}"
PATTERN="${INPUT_PATTERN:-**/*.zip}"
RECURSIVE="${INPUT_RECURSIVE:-true}"
DESTINATION="${INPUT_DESTINATION:-alongside}"
FLATTEN="${INPUT_FLATTEN:-false}"
OVERWRITE="${INPUT_OVERWRITE:-true}"
DELETE_ZIP="${INPUT_DELETE_ZIP:-false}"
FAIL_ON_EMPTY="${INPUT_FAIL_ON_EMPTY:-false}"
DO_COMMIT="${INPUT_COMMIT:-false}"
COMMIT_MESSAGE="${INPUT_COMMIT_MESSAGE:-chore: unzip archives [skip ci]}"
COMMIT_USER_NAME="${INPUT_COMMIT_USER_NAME:-github-actions[bot]}"
COMMIT_USER_EMAIL="${INPUT_COMMIT_USER_EMAIL:-github-actions[bot]@users.noreply.github.com}"

# Output sink: use $GITHUB_OUTPUT on CI, otherwise a throwaway temp file.
GITHUB_OUTPUT="${GITHUB_OUTPUT:-$(mktemp)}"

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

command -v unzip >/dev/null 2>&1 || fail "The 'unzip' command is required but was not found on the runner."

[ -d "$SEARCH_PATH" ] || fail "Search path '$SEARCH_PATH' does not exist or is not a directory."

# ---------------------------------------------------------------------------
# Discover archives
# ---------------------------------------------------------------------------

# If the caller did not use a recursive glob but asked for recursive search,
# prepend '**/' so we walk the whole tree.
if [ "$PATTERN" = "**/*.zip" ] && ! is_true "$RECURSIVE"; then
  PATTERN="*.zip"
fi

group_start "Discovering archives"
log "Search path : $SEARCH_PATH"
log "Pattern     : $PATTERN"
log "Recursive   : $RECURSIVE"

# Enable globstar for '**' and nullglob so an unmatched glob expands to nothing.
shopt -s globstar nullglob

ARCHIVES=()
pushd "$SEARCH_PATH" >/dev/null
for match in $PATTERN; do
  [ -f "$match" ] || continue
  ARCHIVES+=("$match")
done
popd >/dev/null

log "Found ${#ARCHIVES[@]} archive(s)."
group_end

if [ "${#ARCHIVES[@]}" -eq 0 ]; then
  if is_true "$FAIL_ON_EMPTY"; then
    fail "No .zip files matched pattern '$PATTERN' under '$SEARCH_PATH'."
  fi
  log "No archives to extract; nothing to do."
  {
    echo "extracted-count=0"
    echo "extracted-archives="
    echo "output-paths="
    echo "committed=false"
  } >>"$GITHUB_OUTPUT"
  exit 0
fi

# ---------------------------------------------------------------------------
# Extract
# ---------------------------------------------------------------------------

# unzip flags: -o overwrite without prompting, -n never overwrite.
if is_true "$OVERWRITE"; then
  UNZIP_MODE="-o"
else
  UNZIP_MODE="-n"
fi

extracted_archives=()
output_paths=()

for rel in "${ARCHIVES[@]}"; do
  archive="$SEARCH_PATH/$rel"
  archive_dir="$(dirname "$archive")"
  base="$(basename "$rel")"
  name="${base%.zip}"

  # Resolve the target directory for this archive.
  if [ "$DESTINATION" = "alongside" ]; then
    if is_true "$FLATTEN"; then
      target="$archive_dir"
    else
      target="$archive_dir/$name"
    fi
  else
    if is_true "$FLATTEN"; then
      target="$DESTINATION"
    else
      target="$DESTINATION/$name"
    fi
  fi

  group_start "Extracting $archive -> $target"
  mkdir -p "$target"

  if unzip -q $UNZIP_MODE "$archive" -d "$target"; then
    log "Extracted successfully."
  else
    group_end
    fail "Failed to extract '$archive'."
  fi

  if is_true "$DELETE_ZIP"; then
    rm -f "$archive"
    log "Deleted source archive '$archive'."
  fi

  group_end

  extracted_archives+=("$archive")
  output_paths+=("$target")
done

log "Extracted ${#extracted_archives[@]} archive(s)."

# ---------------------------------------------------------------------------
# Optional commit
# ---------------------------------------------------------------------------

committed="false"

if is_true "$DO_COMMIT"; then
  group_start "Committing extracted files"
  git config user.name "$COMMIT_USER_NAME"
  git config user.email "$COMMIT_USER_EMAIL"
  git add -A

  if git diff --cached --quiet; then
    log "No changes to commit."
  else
    git commit -m "$COMMIT_MESSAGE"
    if git push; then
      committed="true"
      log "Committed and pushed extracted files."
    else
      group_end
      fail "Commit succeeded but 'git push' failed. Ensure the workflow has 'contents: write' permission and a checkout with a push-capable token."
    fi
  fi
  group_end
fi

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

{
  echo "extracted-count=${#extracted_archives[@]}"
  echo "committed=$committed"

  echo "extracted-archives<<__EOF__"
  printf '%s\n' "${extracted_archives[@]}"
  echo "__EOF__"

  echo "output-paths<<__EOF__"
  printf '%s\n' "${output_paths[@]}"
  echo "__EOF__"
} >>"$GITHUB_OUTPUT"
