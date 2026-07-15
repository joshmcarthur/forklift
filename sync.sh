#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <upstream> <fork> [branch]" >&2
  exit 1
}

[[ $# -ge 2 && $# -le 3 ]] || usage

upstream="$1"
fork="$2"
branch_arg="${3:-}"

if ! command -v gh >/dev/null 2>&1; then
  echo "✗ $fork failed: gh CLI is not installed" >&2
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
