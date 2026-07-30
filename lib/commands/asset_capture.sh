#!/usr/bin/env bash
# lib/commands/asset_capture.sh — `archwright asset capture`
#
# system -> workspace direction (ADR 0014). Copies one real file into the
# workspace's content-addressed payload store and writes/updates its
# manifest. Every gate below is documented in
# docs/decisions/0014-declared-assets-and-capture-restore-lifecycle.md;
# this file is the reference implementation, not a re-derivation of the
# rules — if the two disagree, the ADR says why, this file has a bug.
#
# No `set -e`/`-u`/`pipefail` here — see the note in lib/contract.sh.

readonly ARCHWRIGHT_ASSET_DEFAULT_MAX_SIZE=52428800  # 50 MiB

# --- internal helpers ------------------------------------------------------

# _asset_capture_type_reason <path> -> prints a reason and returns 0 if
# <path> is NOT an acceptable capture input (missing, symlink, directory,
# or any non-regular special file); returns 1 (silently) if it's fine.
_asset_capture_type_reason() {
  local path="$1"
  if [[ -L "$path" ]]; then printf 'symlinks are not accepted as capture input, no override exists'; return 0; fi
  if [[ ! -e "$path" ]]; then printf 'does not exist'; return 0; fi
  if [[ -d "$path" ]]; then printf 'directories are not supported in v1, only individual regular files'; return 0; fi
  if [[ -S "$path" ]]; then printf 'sockets are not regular files'; return 0; fi
  if [[ -p "$path" ]]; then printf 'FIFOs are not regular files'; return 0; fi
  if [[ -b "$path" || -c "$path" ]]; then printf 'device files are not regular files'; return 0; fi
  if [[ ! -f "$path" ]]; then printf 'is not a regular file'; return 0; fi
  return 1
}

# _asset_capture_denylist_reason <resolved-path> <resolved-home> -> prints a
# reason and returns 0 if <resolved-path> hits the hard denylist (no
# override, ever); returns 1 if it doesn't.
_asset_capture_denylist_reason() {
  local real="$1" home="$2"
  local rel="${real#"$home"/}"
  case "$rel" in
    .ssh|.ssh/*) printf 'under ~/.ssh'; return 0 ;;
    .gnupg|.gnupg/*) printf 'under ~/.gnupg'; return 0 ;;
  esac
  local base
  base="$(basename "$real")"
  case "$base" in
    .env|.env.*) printf 'looks like an environment/secrets file (.env*)'; return 0 ;;
    *.pem) printf 'looks like a PEM key/certificate (*.pem)'; return 0 ;;
    *.key) printf 'looks like a key file (*.key)'; return 0 ;;
    id_rsa*|id_ed25519*|id_ecdsa*|id_dsa*) printf 'looks like an SSH private key (id_*)'; return 0 ;;
    *.p12|*.pfx) printf 'looks like a key/cert bundle (*.p12/*.pfx)'; return 0 ;;
    *.crt) printf 'looks like a certificate (*.crt)'; return 0 ;;
    .bash_history|.zsh_history|.python_history|.sh_history|*_history) printf 'looks like a shell/tool history file'; return 0 ;;
  esac
  return 1
}

# _asset_capture_default_id <dest-path> -> prints a best-effort slug.
# Caller must still validate the result against ARCHWRIGHT_ASSET_ID_PATTERN
# (a pathological dest_path can still fail to produce a valid id).
_asset_capture_default_id() {
  local dest_path="$1" id
  id="$(printf '%s' "$dest_path" | tr '[:upper:]' '[:lower:]' | tr '/' '-')"
  id="$(printf '%s' "$id" | sed -E 's/[^a-z0-9._-]+/-/g; s/^[^a-z0-9]+//')"
  printf '%s' "$id"
}

# --- command -----------------------------------------------------------

cmd_asset_capture() {
  local path="" workspace="" id="" allow_executable=0
  local max_size="$ARCHWRIGHT_ASSET_DEFAULT_MAX_SIZE"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace)
        [[ $# -ge 2 ]] || archwright_die "$EXIT_UNEXPECTED" "--workspace requires a value"
        workspace="$2"; shift 2 ;;
      --id)
        [[ $# -ge 2 ]] || archwright_die "$EXIT_UNEXPECTED" "--id requires a value"
        id="$2"; shift 2 ;;
      --allow-executable)
        allow_executable=1; shift ;;
      --max-size)
        [[ $# -ge 2 ]] || archwright_die "$EXIT_UNEXPECTED" "--max-size requires a value"
        max_size="$2"; shift 2 ;;
      --)
        shift ;;
      -*)
        archwright_die "$EXIT_UNEXPECTED" "unknown argument: $1" ;;
      *)
        [[ -z "$path" ]] || archwright_die "$EXIT_UNEXPECTED" "unexpected extra argument: $1"
        path="$1"; shift ;;
    esac
  done

  [[ -n "$path" ]] || archwright_die "$EXIT_UNEXPECTED" "usage: archwright asset capture <path> --workspace <dir> [--id <slug>] [--allow-executable] [--max-size <bytes>]"
  [[ -n "$workspace" ]] || archwright_die "$EXIT_UNEXPECTED" "--workspace is required"
  [[ -d "$workspace" ]] || archwright_die "$EXIT_UNEXPECTED" "workspace directory not found: ${workspace}"
  workspace="$(cd "$workspace" && pwd)"
  [[ "$max_size" =~ ^[0-9]+$ ]] || archwright_die "$EXIT_UNEXPECTED" "--max-size must be a non-negative integer"
  if [[ -n "$id" && ! "$id" =~ $ARCHWRIGHT_ASSET_ID_PATTERN ]]; then
    archwright_die "$EXIT_UNEXPECTED" "--id '${id}' does not match ${ARCHWRIGHT_ASSET_ID_PATTERN}"
  fi

  [[ -n "${HOME:-}" ]] || archwright_die "$EXIT_UNEXPECTED" "\$HOME is not set"
  local home
  home="$(realpath -e -- "$HOME" 2>/dev/null)" || archwright_die "$EXIT_UNEXPECTED" "cannot resolve \$HOME (${HOME})"

  local reason
  if reason="$(_asset_capture_type_reason "$path")"; then
    archwright_warn "asset capture: ${path}: ${reason}"
    return "$EXIT_VALIDATION_ERROR"
  fi

  local real
  if ! real="$(realpath -e -- "$path" 2>/dev/null)"; then
    archwright_warn "asset capture: ${path}: cannot resolve"
    return "$EXIT_VALIDATION_ERROR"
  fi
  case "$real" in
    "$home"|"$home"/*) : ;;
    *)
      archwright_warn "asset capture: ${path}: resolves to '${real}', outside \$HOME ('${home}') — refusing, no override exists"
      return "$EXIT_VALIDATION_ERROR"
      ;;
  esac

  if reason="$(_asset_capture_denylist_reason "$real" "$home")"; then
    archwright_warn "asset capture: ${path}: refused — ${reason} (no override exists for this check)"
    return "$EXIT_VALIDATION_ERROR"
  fi

  local size
  size="$(stat -c%s -- "$real")"
  if [[ "$size" -gt "$max_size" ]]; then
    archwright_warn "asset capture: ${path}: size ${size} bytes exceeds limit ${max_size} bytes (override with --max-size)"
    return "$EXIT_VALIDATION_ERROR"
  fi

  local raw_mode captured_mode
  raw_mode="$(stat -c%a -- "$real")"
  captured_mode="$(printf '%04o' "$(( 8#${raw_mode} & 8#777 ))")"
  if (( (8#${captured_mode} & 8#111) != 0 )) && [[ "$allow_executable" -ne 1 ]]; then
    archwright_warn "asset capture: ${path}: has an executable bit set; pass --allow-executable to accept it"
    return "$EXIT_VALIDATION_ERROR"
  fi

  local pre_hash
  pre_hash="$(sha256sum -- "$real" | cut -d' ' -f1)"

  mkdir -p "${workspace}/assets/manifest" "${workspace}/assets/payload" || {
    archwright_warn "asset capture: cannot create assets/ under ${workspace}"
    return "$EXIT_UNEXPECTED"
  }

  local tmp
  tmp="$(mktemp "${workspace}/assets/payload/.capture.XXXXXX")" || {
    archwright_warn "asset capture: cannot create a temporary payload file"
    return "$EXIT_UNEXPECTED"
  }
  if ! cp --no-preserve=mode,ownership -- "$real" "$tmp"; then
    rm -f "$tmp"
    archwright_warn "asset capture: failed to copy ${path}"
    return "$EXIT_UNEXPECTED"
  fi

  local post_hash
  post_hash="$(sha256sum -- "$real" | cut -d' ' -f1)"
  if [[ "$post_hash" != "$pre_hash" ]]; then
    rm -f "$tmp"
    archwright_warn "asset capture: ${path}: content changed while it was being captured (TOCTOU) — retry"
    return "$EXIT_VALIDATION_ERROR"
  fi

  local final_payload
  final_payload="$(archwright_asset_payload_path "$workspace" "$pre_hash")"
  mkdir -p "$(dirname "$final_payload")"
  if [[ -f "$final_payload" ]]; then
    rm -f "$tmp"  # identical content already stored under this hash (dedup)
  else
    mv "$tmp" "$final_payload"
    chmod 0644 "$final_payload" 2>/dev/null || true
  fi

  local dest_path="${real#"$home"/}"

  if [[ -z "$id" ]]; then
    id="$(_asset_capture_default_id "$dest_path")"
    if [[ ! "$id" =~ $ARCHWRIGHT_ASSET_ID_PATTERN ]]; then
      archwright_warn "asset capture: could not derive a valid id from '${dest_path}', pass --id explicitly"
      return "$EXIT_VALIDATION_ERROR"
    fi
  fi

  local manifest_file="${workspace}/assets/manifest/${id}.conf"
  local new_content
  new_content="$(printf 'dest_class=home\ndest_path=%s\npayload_sha256=%s\nsize=%s\nmode=%s' \
    "$dest_path" "$pre_hash" "$size" "$captured_mode")"

  if [[ -f "$manifest_file" ]]; then
    local existing_dest_path
    existing_dest_path="$(archwright_parse_asset_manifest_file "$manifest_file" 2>/dev/null | awk -F'\t' '$1=="dest_path"{print $2}')"
    if [[ -n "$existing_dest_path" && "$existing_dest_path" != "$dest_path" ]]; then
      archwright_warn "asset capture: id '${id}' already declares a different dest_path ('${existing_dest_path}'), pass a different --id"
      return "$EXIT_VALIDATION_ERROR"
    fi
    local existing_content
    existing_content="$(cat -- "$manifest_file")"
    if [[ "$existing_content" == "$new_content" ]]; then
      archwright_log asset capture "$id" ok "already declared, nothing to update"
      return "$EXIT_OK"
    fi
  fi

  printf '%s\n' "$new_content" > "$manifest_file"
  archwright_log asset capture "$id" declared "dest=${dest_path} sha256=${pre_hash}"
  return "$EXIT_CHANGED"
}
