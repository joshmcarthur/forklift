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

ignore='[]'
config_account=""
if [[ -n "$config_file" ]]; then
  if [[ ! -f "$config_file" ]]; then
    log "config file not found: $config_file"
    exit 1
  fi
  ignore="$(jq -c '.ignore // []' "$config_file")"
  config_account="$(jq -r '.account // empty' "$config_file")"
fi

if [[ -z "$account" ]]; then
  account="${config_account:-$(gh api user --jq .login)}"
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
discovered="$tmpdir/discovered.json"

gh repo list "$account" --fork --no-archived --limit 1000 \
  --json nameWithOwner,parent,defaultBranchRef \
| jq --argjson ignore "$ignore" '
  [.[] |
    select(.parent != null) |
    select(.nameWithOwner as $fork | ($ignore | index($fork)) | not) |
    {
      fork: .nameWithOwner,
      upstream: (.parent.owner.login + "/" + .parent.name),
      branch: (.parent.defaultBranchRef.name // .defaultBranchRef.name // "main")
    }
  ] | sort_by(.fork)
' >"$discovered"

write_output() {
  local file="$1"
  if [[ -n "$output_file" ]]; then
    jq '.' "$file" >"$output_file"
  else
    jq '.' "$file"
  fi
}

if [[ -z "$config_file" ]]; then
  if [[ -n "$output_file" ]]; then
    jq -n --slurpfile forks "$discovered" '{forks: $forks[0]}' >"$output_file"
  else
    jq -n --slurpfile forks "$discovered" '{forks: $forks[0]}'
  fi
  exit 0
fi

before_forks="$(jq -c '[.forks[]?.fork] | sort' "$config_file")"
merged="$tmpdir/merged.json"

jq -s --arg account "$account" '
  .[0] as $cfg |
  .[1] as $disc |
  (($cfg.forks // []) | INDEX(.fork)) as $existing |
  {
    account: ($cfg.account // $account),
    ignore: ($cfg.ignore // []),
    forks: [
      $disc[] |
      if $existing[.fork] then $existing[.fork] else . end
    ]
  }
' "$config_file" "$discovered" >"$merged"

after_forks="$(jq -c '[.forks[]?.fork] | sort' "$merged")"
if [[ "$before_forks" != "$after_forks" ]]; then
  jq -n --argjson before "$before_forks" --argjson after "$after_forks" '
    (($after - $before)[]? | "+ added \(.)"),
    (($before - $after)[]? | "- removed \(.)")
  ' -r | while IFS= read -r line; do
    [[ -n "$line" ]] && log "$line"
  done
  write_output "$merged"
  exit 2
fi

write_output "$merged"
exit 0
