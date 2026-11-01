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
- **Pick a direction**: one folder under `plans/` decides what gets installed and how dsh boots — full / chat / harness (see [docs/PLANS.md](docs/PLANS.md)). Directions are data: changing a plugin list needs no image rebuild.

## Quick start

```bash
git clone https://github.com/ChenXu233/oh-my-dsh-pack.git
cd oh-my-dsh-pack
sudo ./scripts/up.sh            # full by default; also chat / harness
sudo docker compose logs dsh | grep 'dsh web:'   # copy the tokenized login URL
```

Requires Docker + Compose v2. On first start the profile is initialized from the bundled dsh template, then the selected direction installs its plugins and boots.

## Pick a direction

| Direction | What you get | Image |
|---|---|---|
| `full` | my complete tuned setup (default) | capable |
| `chat` | open-and-chat; plugin list to be chosen | slim |
| `harness` | subscription-grade output self-hosted: docs / sheets / PPT / web research / scheduled tasks; plugin list to be chosen | capable |

```bash
sudo ./scripts/up.sh                 # full
sudo ./scripts/up.sh chat
sudo ./scripts/up.sh harness
```

`capable` adds Python + LibreOffice + CJK fonts for documents and decks; `slim` is enough for chat.
Directions are data: `plans/<direction>/plugins.txt` is mounted into the container, so changing it
needs a `git pull` + restart, not an image rebuild.

On your own domain, set `DSH_PUBLIC_URL` / `DSH_TRUSTED_HOST` in `.env` (or the environment).
Details in [docs/PLANS.md](docs/PLANS.md).

## Layout

| Path | Purpose |
|---|---|
| `Dockerfile` | node:22-slim + global dsh, non-root, capped heap; two env targets (`slim` / `capable`) |
| `entrypoint.sh` | run bootstrap hooks → hand off to `scripts/plan-boot.sh` |
| `plans/<direction>/` | **edit me**: direction (`plan.env`) + plugin list (`plugins.txt`); mounted, not baked |
| `scripts/up.sh` | boot one direction (or the dev instance) |
| `docs/PLANS.md` | the direction matrix, how to add/switch one |
| `docs/DEPLOY.md` | deploy, update, rollback, secrets, troubleshooting |
| `docker-compose.yml` | production instance: ports / volumes / memory cap / healthcheck |
| `docker-compose.dev.yml` | dev instance: separate project/volumes/port + plugin sources mounted |
| `.cnb.yml` | CNB pipeline: verify → artifact registry → GitHub mirror → tag-only deploy |
| `deploy/install.sh` | one-shot server deploy/update |
| `AGENT.md` | **rules for agents working in this repo**: what needs an image rebuild, what does not |

## How plugins get installed (pick your lane)

| Lane | Who it is for | What a code change costs |
|---|---|---|
| **Published** | everyone | list npm package names in `plans/<direction>/plugins.txt`; the list is mounted, so it takes a `git pull` + restart, not an image rebuild. Changing the plugin's own code still means publishing a release |
| **Dev instance** | the plugin author only | `./scripts/up.sh dev` + `bootstrap-dev/`: source is mounted into a blank dsh and installed with `link:`, so a change only needs the built output synced and a restart |

`bootstrap-dev/`, `docker-compose.dev.yml` and `scripts/sync-plugin.ps1` are the author's personal
scaffolding. **You probably do not want them**: add your own package names to
`plans/<direction>/plugins.txt`, or install plugins from the web plugin manager after startup.
See [AGENT.md](AGENT.md).

## Where your data lives

| Content | Location | After container recreation |
|---|---|---|
| Plugins / sessions / API keys / settings | `dsh-home` volume | ✅ kept |
| Agent workspace files | `dsh-workspace` volume | ✅ kept |
| Terminal processes / temp files | container layer | ❌ gone (expected) |

The dev instance uses its own `dsh-dev-home` / `dsh-dev-workspace` volumes, so plugin experiments
never touch production state.

Note: after a major dsh upgrade, plugins inside the volume may be blocked by the `engines.dsh` compatibility check — update or exempt them in the web plugin manager.

## Updating

```bash
git pull && sudo docker compose pull && sudo docker compose up -d --force-recreate
```

## Credits & disclaimer

- Built on [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness); all dsh capabilities belong to its authors
- This repo contains deployment orchestration and personal config only — it does **not** include or redistribute dsh source (the image installs the official npm package at build time)
- Credentials (API keys etc.) live only in volumes on your own machine; this repo ships no secrets

## License

[MIT](LICENSE)
