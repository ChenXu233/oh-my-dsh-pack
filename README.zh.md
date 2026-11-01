# oh-my-dsh-pack

[English](README.md) | 简体中文

> **ChenXu233's dsh pack** —— 我自己口味调校的 [DeepSeek Harness (dsh)](https://github.com/deepseek-ai/deepseek-harness) Docker 部署包。
>
> **个人配置，非官方。** 开源出来首先方便我自己一键部署，也欢迎朋友拿去体验我优化好的 dsh。
>
> **主仓库在 CNB**（`cnb.cool/ChenXu233/oh-my-dsh-pack`），镜像在那里构建；GitHub 是由流水线自动同步的镜像，改动请往 CNB 提。

## 这是什么

一个把 dsh web 跑进 Docker 的"全家桶"：镜像构建、流水线、部署脚本、私人插件预装清单，全部配置即代码。

- **一条命令部署**：`docker compose up -d`，鉴权由 dsh 内置（启动 token → 签名 cookie），无需任何鉴权插件
- **国内分钟级 CI**：CNB 云原生构建自动出镜像（`docker.cnb.cool/<you>/oh-my-dsh-pack`），推 GitHub 自动镜像
- **数据全在卷里**：插件、会话、API Key、工作区都在 named volumes，升级镜像零丢失
- **安装方向可选**：`plans/<方向>/` 一份配置决定装什么、怎么起 —— 全量 / 聊天 / 能力全量，见 [docs/PLANS.md](docs/PLANS.md)。方向是数据，改插件清单不用重建镜像。

## 快速开始

```bash
git clone https://github.com/ChenXu233/oh-my-dsh-pack.git
cd oh-my-dsh-pack
sudo ./scripts/up.sh            # 默认 full，也可 chat / harness
sudo docker compose logs dsh | grep 'dsh web:'   # 复制带 token 的登录 URL
```

前置：Docker + Compose v2。首次启动会从 dsh 随附模板初始化 profile，然后按选中的方向装插件、启动。

## 选一个方向

| 方向 | 是什么 | 镜像 |
|---|---|---|
| `full` | 我本人在用的完整风味（默认） | capable |
| `chat` | 打开就聊；插件清单待选 | slim |
| `harness` | 订阅版能力自建：文档 / 表格 / PPT / 联网研究 / 定时任务；插件清单待选 | capable |

```bash
sudo ./scripts/up.sh                 # full
sudo ./scripts/up.sh chat
sudo ./scripts/up.sh harness
```

`capable` 档多带 Python + LibreOffice + 中文字体，用于做文档和 PPT；只想聊天用 `slim` 就够。
方向是数据：`plans/<方向>/plugins.txt` 挂载进容器，改清单只需 git pull + 重启，不用重建镜像。

部署到你自己的域名时，在 `.env` 里设 `DSH_PUBLIC_URL` / `DSH_TRUSTED_HOST`（或同名环境变量）。
细节见 [docs/PLANS.md](docs/PLANS.md)。

## 目录

| 路径 | 用途 |
|---|---|
| `Dockerfile` | node:22-slim + 全局 dsh，非 root，堆内存封顶；两档环境（`slim` / `capable`） |
| `entrypoint.sh` | 跑 bootstrap → 交给 `scripts/plan-boot.sh` 按方向启动 |
| `plans/<方向>/` | **编辑我**：方向定义（`plan.env`）+ 预装插件清单（`plugins.txt`）；挂载，不烤进镜像 |
| `scripts/up.sh` | 选一个方向启动（或起开发实例） |
| `docs/PLANS.md` | 方向矩阵、加方向/切方向的步骤 |
| `docs/DEPLOY.md` | 部署、发布、回滚、密钥、排错 |
| `docker-compose.yml` | 生产实例：端口/卷/内存上限/健康检查 |
| `docker-compose.dev.yml` | 开发实例：独立 project/卷/端口 + 挂插件源码 |
| `.cnb.yml` | CNB 流水线：验证 → 制品库 → GitHub 镜像 → 仅 tag 部署 |
| `deploy/install.sh` | 服务器端一键部署/更新 |
| `AGENT.md` | **给 agent 看的约定**：改动影响面、什么该进镜像什么不该 |

## 插件怎么装（两条路，先选对）

| 链路 | 用在哪 | 改代码要做什么 |
|---|---|---|
| **发布链路** | 所有人 | 在 `plans/<方向>/plugins.txt` 里填 npm 包名；清单是挂载的，改完 git pull + 重启即可，不用重建镜像。插件自己的代码改动仍要发版 |
| **开发链路** | 只有插件作者本人 | `./scripts/up.sh dev` + `bootstrap-dev/`：源码挂进空白 dsh 用 `link:` 装，改代码只同步产物 + 重启（该包必须零运行时依赖；有依赖的请 `pnpm pack` 后用 tgz 装） |

`bootstrap-dev/`、`docker-compose.dev.yml`、`scripts/sync-plugin.ps1` 是作者本人的开发脚手架。
**你多半不需要它们**：要插件就改 `plans/<方向>/plugins.txt`，或启动后在网页插件管理器里装。
详见 [AGENT.md](AGENT.md)。

## 数据都在哪

| 内容 | 位置 | 重建容器后 |
|---|---|---|
| 插件 / 会话 / API Key / 设置 | `dsh-home` 卷 | ✅ 保留 |
| agent 工作区文件 | `dsh-workspace` 卷 | ✅ 保留 |
| 终端进程 / 临时文件 | 容器层 | ❌ 重建即失 |

开发实例用独立的 `dsh-dev-home` / `dsh-dev-workspace` 卷，插件实验不会碰到生产状态。

注意：升级 dsh 大版本后，卷内旧插件可能因 `engines.dsh` 兼容范围被启动检查拦下，在网页插件管理器里更新或豁免即可。

## 更新

```bash
git pull && sudo docker compose pull && sudo docker compose up -d --force-recreate
```

## 致谢与声明

- 基于 [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)，dsh 的所有能力归其作者所有
- 本仓库只包含部署编排与个人配置，**不含也不分发 dsh 源码**（镜像构建时从 npm 安装官方包）
- 凭据（API Key 等）只存在你自己机器的卷里，本仓库不含任何密钥
