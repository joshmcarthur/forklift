# Forklift

Forklift keeps your GitHub forks synchronised with their upstream repositories from a single controller repository.

Instead of clicking "Sync fork" on each repository or adding a workflow to every fork, Forklift runs from one repo and manages many forks on a schedule.

## How it works

1. **Discover** — daily workflow lists your forks and opens a PR when `repos.json` should change
2. **Sync** — daily workflow mirror-syncs each configured fork to upstream with `gh repo sync --force`

New forks are picked up automatically. Add forks to `ignore` if you do not want them synced.

## One-time setup

### 1. Create the `FORKLIFT_TOKEN` secret

`GITHUB_TOKEN` only has access to this controller repository. Forklift needs a Personal Access Token that can read and write your forks.

Create a secret named `FORKLIFT_TOKEN` on this repository:

- **Classic PAT**: `repo` scope
- **Fine-grained PAT**: read/write on each fork you want to sync

The workflows pass this to `gh` as `GH_TOKEN`.

### 2. Enable Actions pull request creation

In repository **Settings → Actions → General → Workflow permissions**, enable **"Allow GitHub Actions to create and approve pull requests"**.

This is required for the discover workflow to open PRs when your fork list changes.

## Configuration

[`repos.json`](repos.json) controls Forklift:

```json
{
  "account": "your-github-username",
  "ignore": [
    "your-github-username/experiment-fork"
  ],
  "forks": [
    {
      "upstream": "neovim/neovim",
      "fork": "your-github-username/neovim",
      "branch": "master"
    }
  ]
}
```

| Field | Description |
|-------|-------------|
| `account` | GitHub user whose forks to discover |
| `ignore` | Fork names (`owner/repo`) excluded from sync |
| `forks` | Repositories to mirror-sync |

### Ignoring a fork

Add the fork name to `ignore`:

```json
"ignore": ["your-github-username/my-fork-with-local-changes"]
```

The next discovery run removes it from `forks` via PR.

### Bootstrapping config locally

```bash
export GH_TOKEN=<your-pat>   # or use gh auth login

# Create initial config
./discover.sh your-github-username | \
  jq '{account: "your-github-username", ignore: [], forks: .forks}' > repos.json

# Refresh fork list (respects ignore, preserves branch overrides)
./discover.sh --config repos.json -o repos.json
```

## Scripts

### `discover.sh`

Lists forks for a GitHub account and updates `repos.json`. By default only **public** forks are discovered; pass `--include-private` to include private forks as well.

```bash
./discover.sh                              # print JSON to stdout (public forks only)
./discover.sh your-github-username         # specific account
./discover.sh --config repos.json -o repos.json
./discover.sh --include-private --config repos.json -o repos.json
```

Exits with code `2` when `--config` is used and the `forks` list changed.

### `sync.sh`

Mirror-syncs one fork to upstream:

```bash
./sync.sh <upstream> <fork> <branch>

# Example
./sync.sh neovim/neovim your-github-username/neovim master
```

Divergent commits on the fork are overwritten (`--force`).

## Workflows

| Workflow | Schedule | Purpose |
|----------|----------|---------|
| [Discover forks](.github/workflows/discover.yml) | Daily 02:00 UTC | Update `repos.json` via PR |
| [Sync forks](.github/workflows/sync.yml) | Daily 03:00 UTC | Mirror-sync all configured forks |
| [Lint workflows](.github/workflows/lint.yml) | On workflow changes | Run [actionlint](https://github.com/rhysd/actionlint) |

All workflows can also be triggered manually via **Actions → Run workflow**.

### Viewing results

- **Sync summary**: workflow run summary shows per-fork success/failure
- **Per-fork logs**: each matrix job logs details for one fork
- **Discovery PRs**: review added/removed forks before merging

## Workflow maintenance

- **actionlint** runs on pull requests that change `.github/workflows/**`
- **Dependabot** opens weekly PRs to bump GitHub Actions versions (see [`.github/dependabot.yml`](.github/dependabot.yml))

## Non-goals

- Managing development branches
- Automatically merging custom changes into upstream
- Replacing GitHub's fork workflow for active contributors

## License

MIT
