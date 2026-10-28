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
- **Pick an install plan**: one folder per plan under `plans/` decides what gets installed and how dsh boots — full / minimal / chat / capability-complete / headless coder (see [docs/PLANS.md](docs/PLANS.md))

## Quick start

```bash
git clone https://github.com/ChenXu233/oh-my-dsh-pack.git
cd oh-my-dsh-pack
sudo ./scripts/up.sh            # full by default; also mini / chat / harness
sudo docker compose logs dsh | grep 'dsh web:'   # copy the tokenized login URL
```

Requires Docker + Compose v2. On first start the profile is initialized from the bundled dsh template, then the selected plan installs its plugins and boots.

## Pick a plan

| Plan | What you get | Image |
|---|---|---|
| `full` | my complete tuned setup (default) | capable |
| `mini` | dsh itself, no preinstalled plugins | slim |
| `chat` | open-and-chat: memory, thinking tiers, rich text, images, notifications | slim |
| `harness` | subscription-grade output self-hosted: docs / sheets / PPT / web research / scheduled tasks, with your own models and quota | capable |
| `coder` | headless coder: one task in, result on stdout | slim |

```bash
sudo ./scripts/up.sh                 # full
sudo ./scripts/up.sh mini
sudo ./scripts/up.sh harness
sudo ./scripts/up.sh coder "fix the failing tests"
```

`capable` adds Python + LibreOffice + CJK fonts for documents and decks; `slim` is enough for chat.

On your own domain, set `DSH_PUBLIC_URL` / `DSH_TRUSTED_HOST` in `docker-compose.yml` (or the environment).
Details in [docs/PLANS.md](docs/PLANS.md).

## Layout

| Path | Purpose |
|---|---|
| `Dockerfile` | node:22-slim + global dsh, non-root, capped heap |
| `entrypoint.sh` | run bootstrap hooks → hand off to `scripts/plan-boot.sh` |
| `plans/<plan>/` | **edit me**: plan definition (`plan.env`) + plugin list (`plugins.txt`) |
| `scripts/up.sh` | boot one plan (headless plans run a task directly) |
| `docs/PLANS.md` | the five plans, what switching costs, how to add one |
| `docker-compose.yml` | ports / volumes / memory cap / healthcheck |
| `.cnb.yml` | CNB pipeline: build → artifact registry → GitHub mirror → (optional) SSH deploy |
| `deploy/install.sh` | one-shot server deploy/update |
| `AGENT.md` | **rules for agents working in this repo**: what needs an image rebuild, what does not |
| `bootstrap-dev/` + `docker-compose.dev.yml` | the *author's own* publish-free dev loop (see below) |

## How plugins get installed (pick your lane)

| Lane | Who it is for | What a code change costs |
|---|---|---|
| **Published** | everyone | list npm package names in `plans/<plan>/plugins.txt`; changing code means publishing a release and rebuilding the image |
| **Dev loop** | the plugin author only | `bootstrap-dev/` + `docker-compose.dev.yml`: source is mounted into the container and installed with `link:`, so a change only needs the built output synced and a container restart |

`bootstrap-dev/`, `docker-compose.dev.yml` and `scripts/sync-plugin.ps1` are the author's personal
scaffolding. **You probably do not want them**: add your own package names to
`plans/<plan>/plugins.txt`, or install plugins from the web plugin manager after startup.
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
