#!/usr/bin/env bash
# scripts/check-secrets.sh — basic secret/PII scanner for THIS repository.
#
# Not a substitute for a real secret-scanning tool (gitleaks, trufflehog);
# it exists as a cheap, dependency-free, always-available first line of
# defense that runs in CI on every push and can be run locally before a
# commit. See docs/decisions/ for why the framework repo must never
# contain personal data at all (unlike a private workspace, which is
# allowed secrets — just encrypted ones, per the broader architecture).
#
# Usage: scripts/check-secrets.sh [path]   (default: repo root)
# Exit 0: nothing found. Exit 1: findings printed to stderr.
set -uo pipefail

TARGET="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FOUND=0

report() {
  local pattern_desc="$1" file="$2" line="$3"
  echo "[check-secrets] possible ${pattern_desc}: ${file}:${line}" >&2
  FOUND=1
}

# grep over tracked-and-trackable text files, excluding .git and this
# script's own pattern definitions (which necessarily *mention* the
# patterns they look for).
scan() {
  local desc="$1" pattern="$2"
  local match
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    local file="${match%%:*}"
    local rest="${match#*:}"
    local lineno="${rest%%:*}"
    report "$desc" "$file" "$lineno"
  done < <(
    grep -rEn \
      --exclude-dir=.git \
      --exclude="$(basename "${BASH_SOURCE[0]}")" \
      -e "$pattern" \
      "$TARGET" 2>/dev/null
  )
}

scan "PEM private key header"            '-----BEGIN (RSA |EC |OPENSSH |DSA |)PRIVATE KEY-----'
scan "age secret key"                    'AGE-SECRET-KEY-1[A-Z0-9]+'
scan "AWS access key ID"                 '\bAKIA[0-9A-Z]{16}\b'
scan "GitHub token"                      '\bgh[pousr]_[A-Za-z0-9]{20,}\b'
scan "Slack token"                       '\bxox[baprs]-[A-Za-z0-9-]{10,}\b'
scan "generic sk- style API token"       '\bsk-[A-Za-z0-9]{20,}\b'
scan "hardcoded password/secret/token assignment with a real-looking value" \
  '\b(password|passwd|secret|api[_-]?key|access[_-]?token)\b[[:space:]]*[:=][[:space:]]*['"'"'"][^'"'"'"[:space:]]{6,}['"'"'"]'
scan "personal home directory path"      '/home/[A-Za-z0-9_-]+'
scan "email address"                     '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'

if [[ "$FOUND" -ne 0 ]]; then
  echo "[check-secrets] FAILED — findings above must be removed before this repository is public." >&2
  exit 1
fi

echo "[check-secrets] OK — no findings in ${TARGET}"
exit 0
