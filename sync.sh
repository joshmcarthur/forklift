#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <upstream> <fork> <branch>" >&2
  exit 1
}

[[ $# -eq 3 ]] || usage

upstream="$1"
fork="$2"
branch="$3"

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

if ! gh api "repos/$upstream/branches/$branch" >/dev/null 2>&1; then
  echo "✗ $fork failed: branch '$branch' does not exist on upstream $upstream" >&2
  exit 1
fi

if ! gh repo sync "$fork" --source "$upstream" -b "$branch" --force; then
  echo "✗ $fork failed: gh repo sync failed" >&2
  exit 1
fi

echo "✓ $fork synced"
exit 0
