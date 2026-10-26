# oh-my-dsh-pack

> **ChenXu233's dsh pack** — my personal, opinionated Docker deployment kit for [DeepSeek Harness (dsh)](https://github.com/deepseek-ai/deepseek-harness).
>
> **This is a personal config, not an official distribution.** It exists so I can redeploy my tuned dsh anywhere in one command — and so friends can try my setup too.
>
> **The source of truth is on CNB** (`cnb.cool/ChenXu233/oh-my-dsh-pack`), where the image is built; GitHub is a mirror the pipeline syncs automatically. Send changes to CNB.

[简体中文](README.zh.md) | English

## What is this

A "batteries-included" kit that runs the dsh web GUI in Docker: image build, CI pipeline, deploy scripts, and my must-have plugin bootstrap — everything as code.

- **One-command deploy**: `docker compose up -d`. Auth is built into dsh (launch token → signed cookie), no auth plugin needed
- **Minute-level CI in China**: CNB cloud build publishes images (`docker.cnb.cool/<you>/oh-my-dsh-pack`) and mirrors the repo to GitHub automatically
- **All state in volumes**: plugins, sessions, API keys, and workspaces live in named volumes — image upgrades lose nothing
- **Declarative plugin bootstrap**: `bootstrap/*.sh` runs in order on cold start, reinstalling my plugin list automatically

## Quick start

```bash
git clone https://github.com/ChenXu233/oh-my-dsh-pack.git
cd oh-my-dsh-pack
sudo docker compose up -d
sudo docker compose logs dsh | grep 'dsh web:'   # copy the tokenized login URL
```

Requires Docker + Compose v2. On first start the web profile is initialized from the bundled dsh template, then everything under `bootstrap/` runs.

## Layout

| Path | Purpose |
|---|---|
| `Dockerfile` | node:22-slim + global dsh, non-root, capped heap |
| `entrypoint.sh` | bootstrap plugin pre-install → start dsh web |
| `bootstrap/10-plugins.sh` | **edit me**: your personal must-have plugin list |
| `docker-compose.yml` | ports / volumes / memory cap / healthcheck |
| `.cnb.yml` | CNB pipeline: build → artifact registry → GitHub mirror → (optional) SSH deploy |
| `deploy/install.sh` | one-shot server deploy/update |
| `AGENT.md` | **rules for agents working in this repo**: what needs an image rebuild, what does not |
| `bootstrap-dev/` + `docker-compose.dev.yml` | the *author's own* publish-free dev loop (see below) |

## How plugins get installed (pick your lane)

| Lane | Who it is for | What a code change costs |
|---|---|---|
| **Published** | everyone | list npm package names in `bootstrap/10-plugins.sh`; changing code means publishing a release and rebuilding the image |
| **Dev loop** | the plugin author only | `bootstrap-dev/` + `docker-compose.dev.yml`: source is mounted into the container and installed with `link:`, so a change only needs the built output synced and a container restart |

`bootstrap-dev/`, `docker-compose.dev.yml` and `scripts/sync-mesh.ps1` are the author's personal
scaffolding. **You probably do not want them**: add your own package names to
`bootstrap/10-plugins.sh`, or install plugins from the web plugin manager after startup.
See [AGENT.md](AGENT.md).

## Where your data lives

| Content | Location | After container recreation |
|---|---|---|
| Plugins / sessions / API keys / settings | `dsh-home` volume | ✅ kept |
| Agent workspace files | `dsh-workspace` volume | ✅ kept |
| Terminal processes / temp files | container layer | ❌ gone (expected) |

Note: after a major dsh upgrade, plugins inside the volume may be blocked by the `engines.dsh` compatibility check — update or exempt them in the web plugin manager.

## Updating

```bash
git pull && sudo docker compose pull && sudo docker compose up -d
```

## Credits & disclaimer

- Built on [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness); all dsh capabilities belong to its authors
- This repo contains deployment orchestration and personal config only — it does **not** include or redistribute dsh source (the image installs the official npm package at build time)
- Credentials (API keys etc.) live only in volumes on your own machine; this repo ships no secrets

## License

[MIT](LICENSE)
