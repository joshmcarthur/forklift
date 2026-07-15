#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <upstream> <fork> [branch] [disable-actions]" >&2
  exit 1
}

[[ $# -ge 2 && $# -le 4 ]] || usage

upstream="$1"
fork="$2"
branch_arg="${3:-}"
disable_actions="$(printf '%s' "${4:-true}" | tr '[:upper:]' '[:lower:]')"

actions_perms_file=""
actions_were_enabled=false

restore_fork_actions() {
  if [[ "$actions_were_enabled" != "true" || -z "$actions_perms_file" || ! -f "$actions_perms_file" ]]; then
    return 0
  fi

  if ! jq '.enabled = true' "$actions_perms_file" | \
    gh api -X PUT "repos/$fork/actions/permissions" --input - >/dev/null 2>&1; then
    echo "→ $fork: warning: could not restore Actions permissions" >&2
    return 0
  fi
  echo "→ $fork: restored Actions" >&2
}

suppress_fork_actions_for_sync() {
  [[ "$disable_actions" == "true" ]] || return 0

  local perms enabled
  perms="$(gh api "repos/$fork/actions/permissions")"
  enabled="$(jq -r '.enabled' <<< "$perms")"
  if [[ "$enabled" != "true" ]]; then
    return 0
  fi

  actions_perms_file="$(mktemp)"
  printf '%s' "$perms" > "$actions_perms_file"
  actions_were_enabled=true
  trap restore_fork_actions EXIT

  if ! gh api -X PUT "repos/$fork/actions/permissions" \
    --input - <<< '{"enabled": false}' >/dev/null 2>&1; then
    echo "✗ $fork failed: could not disable Actions for sync" >&2
    exit 1
  fi
  echo "→ $fork: disabled Actions for sync" >&2
}

if ! command -v gh >/dev/null 2>&1; then
  echo "✗ $fork failed: gh CLI is not installed" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "✗ $fork failed: jq is not installed" >&2
  exit 1
fi

if ! gh repo view "$fork" >/dev/null 2>&1; then
  echo "✗ $fork failed: fork does not exist or is not accessible" >&2
  exit 1
fi

parent="$(gh api "repos/$fork" --jq '.parent.full_name // empty' 2>/dev/null || true)"
if [[ -z "$parent" ]]; then
  echo "✗ $fork failed: repository is not a fork" >&2
  exit 1
fi

if [[ "$parent" != "$upstream" ]]; then
  echo "✗ $fork failed: fork parent is '$parent', expected '$upstream'" >&2
  exit 1
fi

upstream_default="$(gh api "repos/$upstream" --jq '.default_branch')"
branch="${branch_arg:-$upstream_default}"

if ! gh api "repos/$upstream/branches/$branch" >/dev/null 2>&1; then
  if [[ "$branch" == "$upstream_default" ]]; then
    echo "✗ $fork failed: upstream default branch '$branch' does not exist on $upstream" >&2
    exit 1
  fi
  echo "→ $fork: branch '$branch' not on upstream; syncing '$upstream_default' instead" >&2
  branch="$upstream_default"
fi

suppress_fork_actions_for_sync

sync_output=""
if ! sync_output="$(gh repo sync "$fork" --source "$upstream" -b "$branch" --force 2>&1)"; then
  if [[ -n "$sync_output" ]]; then
    sync_output="$(printf '%s' "$sync_output" | tr '\n' ' ' | sed -E 's/ +/ /g; s/^ //; s/ $//')"
    echo "✗ $fork failed: $sync_output" >&2
  else
    echo "✗ $fork failed: gh repo sync failed" >&2
  fi
  exit 1
fi

echo "✓ $fork synced ($branch)"
exit 0
