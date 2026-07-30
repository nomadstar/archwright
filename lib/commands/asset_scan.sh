#!/usr/bin/env bash
# lib/commands/asset_scan.sh — `archwright asset scan`
#
# Read-only, heuristic. Never inspects anything the caller didn't name
# explicitly (no implicit full-$HOME scan) — see ADR 0014. For each
# path-shaped reference found inside the given files/directories, reports
# exactly one of: declared, referenced, missing, unparsed. Never makes a
# relevance judgment ("ignored"/"irrelevant" do not exist as outcomes) —
# the human decides what matters, this command only reports facts.
#
# Ambiguity resolved during implementation (documented per ADR 0014's own
# instruction to do so rather than silently invent behavior): the ADR's
# amendment says EXIT_VALIDATION_ERROR applies when "--workspace points at
# an invalid workspace, or an existing manifest file under it fails to
# parse." Running full archwright_validate_workspace (which also requires
# every profiles/*.conf to be well-formed) would make `scan` fail on a
# workspace whose profiles are broken for reasons that have nothing to do
# with assets. `scan` only needs the declared-asset set, so it validates
# assets/ specifically (archwright_validate_asset_manifests), not the
# whole workspace.
#
# No `set -e`/`-u`/`pipefail` here — see the note in lib/contract.sh.

# _asset_scan_resolve <candidate> -> prints the absolute path a `~/...` or
# literal-$HOME-prefixed candidate resolves to.
_asset_scan_resolve() {
  local candidate="$1" home="$2"
  case "$candidate" in
    '~/'*) printf '%s%s\n' "$home" "${candidate#\~}" ;;
    *) printf '%s\n' "$candidate" ;;
  esac
}

cmd_asset_scan() {
  local workspace=""
  local -a inputs=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace)
        [[ $# -ge 2 ]] || archwright_die "$EXIT_UNEXPECTED" "--workspace requires a value"
        workspace="$2"; shift 2 ;;
      --)
        shift ;;
      -*)
        archwright_die "$EXIT_UNEXPECTED" "unknown argument: $1" ;;
      *)
        inputs+=("$1"); shift ;;
    esac
  done

  [[ "${#inputs[@]}" -ge 1 ]] || archwright_die "$EXIT_UNEXPECTED" "usage: archwright asset scan <file-or-dir>... --workspace <dir> (scan never runs with zero explicit inputs)"
  [[ -n "$workspace" ]] || archwright_die "$EXIT_UNEXPECTED" "--workspace is required"
  [[ -d "$workspace" ]] || archwright_die "$EXIT_UNEXPECTED" "workspace directory not found: ${workspace}"
  workspace="$(cd "$workspace" && pwd)"
  [[ -n "${HOME:-}" ]] || archwright_die "$EXIT_UNEXPECTED" "\$HOME is not set"

  if ! archwright_validate_asset_manifests "$workspace"; then
    archwright_warn "asset scan: assets/ under ${workspace} does not validate, see warnings above"
    return "$EXIT_VALIDATION_ERROR"
  fi

  # Build the declared-dest-path set: absolute paths for every valid
  # manifest (dest_class=home is the only value in spec v0.1).
  local declared_paths=""
  shopt -s nullglob
  local manifest_files=("${workspace}"/assets/manifest/*.conf)
  shopt -u nullglob
  local mf id
  for mf in "${manifest_files[@]}"; do
    id="$(basename "$mf" .conf)"
    archwright_try_load_asset_manifest "$workspace" "$id" 2>/dev/null || continue
    declared_paths="${declared_paths}${HOME}/${ARCHWRIGHT_ASSET_DEST_PATH}"$'\n'
  done

  local -a files=()
  local input
  for input in "${inputs[@]}"; do
    if [[ -d "$input" ]]; then
      local f
      while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$input" -type f -print0 2>/dev/null)
    elif [[ -f "$input" && -r "$input" ]]; then
      files+=("$input")
    else
      archwright_warn "asset scan: ${input}: does not exist or is not readable"
      return "$EXIT_UNEXPECTED"
    fi
  done

  local home_escaped
  home_escaped="$(printf '%s' "$HOME" | sed 's/[.[\*^$/]/\\&/g')"
  local resolved_pattern="(~|${home_escaped})/[^[:space:]()]+"
  local unparsed_pattern='(\$[A-Za-z_][A-Za-z0-9_]*/[^[:space:]()]*|~/[^[:space:]()]*[*?][^[:space:]()]*)'

  local seen=""
  local f candidate abs status

  for f in "${files[@]}"; do
    if [[ ! -r "$f" ]]; then
      archwright_warn "asset scan: ${f}: permission denied"
      return "$EXIT_UNEXPECTED"
    fi

    # Unparsed (glob/variable) candidates are extracted FIRST and recorded
    # in $seen so the broader resolved-path pattern below (which would
    # otherwise also match the literal substring of a glob like
    # ~/Pictures/*.png) never reclassifies them as "missing".
    while IFS= read -r candidate; do
      [[ -z "$candidate" ]] && continue
      printf '%s\n' "$seen" | grep -qxF "$candidate" && continue
      seen="${seen}${candidate}"$'\n'
      archwright_log asset scan "$candidate" unparsed
    done < <(grep -ohE "$unparsed_pattern" -- "$f" 2>/dev/null)

    while IFS= read -r candidate; do
      [[ -z "$candidate" ]] && continue
      printf '%s\n' "$seen" | grep -qxF "$candidate" && continue
      seen="${seen}${candidate}"$'\n'

      abs="$(_asset_scan_resolve "$candidate" "$HOME")"
      if [[ -e "$abs" ]]; then
        if printf '%s\n' "$declared_paths" | grep -qxF "$abs"; then
          status=declared
        else
          status=referenced
        fi
      else
        status=missing
      fi
      archwright_log asset scan "$abs" "$status"
    done < <(grep -ohE "$resolved_pattern" -- "$f" 2>/dev/null)
  done

  return "$EXIT_OK"
}
