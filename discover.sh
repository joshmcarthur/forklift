#!/usr/bin/env bash
set -euo pipefail

config_file=""
output_file=""
account=""

usage() {
  cat >&2 <<EOF
Usage: $0 [options] [account]

Options:
  --config FILE   Existing repos.json to merge into (reads account and ignore)
  -o FILE         Write output to FILE instead of stdout
  -h, --help      Show this help
EOF
  exit 1
}

log() {
  echo "$@" >&2
}

resolve_account() {
  if [[ -n "$account" ]]; then
    echo "$account"
    return
  fi

  gh api user --jq .login
}

discover_forks_to_file() {
  local acct="$1"
  local ignore_json="$2"
  local output_file="$3"
  local json

  if ! json="$(gh repo list "$acct" --fork --no-archived --limit 1000 \
    --json nameWithOwner,parent,defaultBranchRef 2>/dev/null)"; then
    log "failed to list forks for account $acct"
    exit 1
  fi

  jq -c --argjson ignore "$ignore_json" '
    [.[] |
      select(.parent != null) |
      select(.nameWithOwner as $fork | ($ignore | index($fork)) | not) |
      {
        fork: .nameWithOwner,
        upstream: (.parent.owner.login + "/" + .parent.name),
        branch: (.parent.defaultBranchRef.name // .defaultBranchRef.name // "main")
      }
    ] | sort_by(.fork)
  ' <<<"$json" >"$output_file"
}

merge_forks_to_file() {
  local discovered_file="$1"
  local existing_file="$2"
  local output_file="$3"

  if jq -e 'length == 0' "$existing_file" >/dev/null; then
    cp "$discovered_file" "$output_file"
    return
  fi

  if jq -e 'length == 0' "$discovered_file" >/dev/null; then
    printf '[]' >"$output_file"
    return
  fi

  jq -c \
    --slurpfile discovered "$discovered_file" \
    --slurpfile existing "$existing_file" \
    '
    ($existing[0] | INDEX(.fork)) as $existing_idx |
    [
      $discovered[0][] | . as $d |
      if $existing_idx[$d.fork] then $existing_idx[$d.fork] else $d end
    ] | sort_by(.fork)
  ' >"$output_file"
}

print_changelog_files() {
  local before_file="$1"
  local after_file="$2"

  jq -r \
    --slurpfile before "$before_file" \
    --slurpfile after "$after_file" \
    '
    ($before[0] | map(.fork)) as $before_forks |
    ($after[0] | map(.fork)) as $after_forks |
    (($after_forks - $before_forks)[] | "+ added \(.)"),
    (($before_forks - $after_forks)[] | "- removed \(.)")
  ' | while IFS= read -r line; do
    [[ -n "$line" ]] && log "$line"
  done
}

forks_changed_files() {
  local before_file="$1"
  local after_file="$2"

  jq -e \
    --slurpfile before "$before_file" \
    --slurpfile after "$after_file" \
    '($before[0] | map(.fork) | sort) != ($after[0] | map(.fork) | sort)' \
    >/dev/null
}

write_config_file() {
  local account="$1"
  local ignore_json="$2"
  local forks_file="$3"

  jq \
    --arg account "$account" \
    --argjson ignore "$ignore_json" \
    --slurpfile forks "$forks_file" \
    '{account: $account, ignore: $ignore, forks: $forks[0]}'
}

write_forks_only_file() {
  local forks_file="$1"

  jq \
    --slurpfile forks "$forks_file" \
    '{forks: $forks[0]}'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || usage
      config_file="$2"
      shift 2
      ;;
    -o)
      [[ $# -ge 2 ]] || usage
      output_file="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    -*)
      log "unknown option: $1"
      usage
      ;;
    *)
      account="$1"
      shift
      ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  log "gh CLI is not installed"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  log "jq is not installed"
  exit 1
fi

ignore_json='[]'
existing_account=""
discovered_file="$(mktemp)"
existing_file="$(mktemp)"
merged_file="$(mktemp)"
cleanup() {
  rm -f "$discovered_file" "$existing_file" "$merged_file"
}
trap cleanup EXIT

printf '[]' >"$existing_file"

if [[ -n "$config_file" ]]; then
  if [[ ! -f "$config_file" ]]; then
    log "config file not found: $config_file"
    exit 1
  fi

  existing_account="$(jq -r '.account // empty' "$config_file")"
  ignore_json="$(jq -c '.ignore // []' "$config_file")"
  jq -c '.forks // []' "$config_file" >"$existing_file"
fi

if [[ -z "$account" && -n "$existing_account" ]]; then
  account="$existing_account"
fi

resolved_account="$(resolve_account)"
discover_forks_to_file "$resolved_account" "$ignore_json" "$discovered_file"
changed=0

if [[ -n "$config_file" ]]; then
  merge_forks_to_file "$discovered_file" "$existing_file" "$merged_file"

  if forks_changed_files "$existing_file" "$merged_file"; then
    print_changelog_files "$existing_file" "$merged_file"
    changed=1
  fi

  if [[ -n "$output_file" ]]; then
    write_config_file "$resolved_account" "$ignore_json" "$merged_file" >"$output_file"
  else
    write_config_file "$resolved_account" "$ignore_json" "$merged_file"
  fi
else
  if [[ -n "$output_file" ]]; then
    write_forks_only_file "$discovered_file" >"$output_file"
  else
    write_forks_only_file "$discovered_file"
  fi
fi

if [[ -n "$config_file" && "$changed" -eq 1 ]]; then
  exit 2
fi

exit 0
