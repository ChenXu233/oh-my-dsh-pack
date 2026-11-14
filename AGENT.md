# AGENT.md

给在本仓库里干活的 AI agent 和人类看的约定。先读索引, 再改任何东西。

## 0. 索引

| 位置 | 是什么 | 什么时候读 |
|---|---|---|
| [docs/DEPLOY.md](docs/DEPLOY.md) | **部署与运维**: 首次部署、发布、回滚、密钥、排错 | 上线 / 排错 |
| [README.md](README.md) / [README.zh.md](README.zh.md) | 对外安装说明、目录说明 | 对外介绍 / 首次部署 |
| `.cnb.yml` | CNB 流水线: push 只验证; tag 才构建+推镜像+部署 | 改 CI 或部署方式 |
| `deploy/dsh-deploy.sh` | 服务器端部署脚本(被受限 key 强制调用) | 改部署步骤 |
| `deploy/install.sh` | 服务器端手工一键部署/更新 | 手工上线 |
| [docs/PLANS.md](docs/PLANS.md) | **方向矩阵**: full/chat/harness/dev、加方向、切方向 | 改方向 / 加方向 |
| `plans/<方向>/plan.env` + `plugins.txt` + `patch.yml` | 方向 = 数据: 环境要求、profile、入口、插件清单、计划级 patch | 改预装插件 / 默认配置 |
| `bootstrap-dev/20-link-plugins.sh` | 开发实例: 遍历 `/opt/dev-plugins/<插件>/` 逐个 `link:`(仅零运行时依赖的包) | 开发插件 |
| `docker-compose.yml` | 生产实例: 端口/卷/内存/健康检查 + 挂载 plans | 改生产编排 |
| `docker-compose.dev.yml` | 开发实例: 独立 project/卷/端口 + 挂源码 | 改开发编排 |
| `scripts/up.sh` | 选方向启动 / 起开发实例 | 启动 |
| `scripts/sync-plugin.ps1` | 本地 build → scp → 重启开发实例 | 每轮迭代 |
| `Dockerfile` | node24 + dsh + pnpm; 两档环境(`slim`/`capable`), 改它必须重建镜像 | 改运行环境 / 加系统依赖 |

## 1. 主仓库是 CNB, GitHub 只是镜像

**规矩: 提交后只推 CNB(`git push cnb main`), 不要推 GitHub。**
GitHub 是流水线用 `tencentcom/git-sync` 推过去的镜像, 手工往 GitHub 推会和流水线抢同一个 ref。

| 远端 | 角色 | 说明 |
|---|---|---|
| `cnb` (`cnb.cool/ChenXu233/oh-my-dsh-pack`) | **唯一真源** | 镜像在这里构建, 流水线在这里跑 |
| `origin` (GitHub) | 只读镜像 | 由 `main.push` / tag 流水线推过去; 不参与构建、部署, 服务器也不从它拉 |

理由: 镜像由 CNB 构建并推到 `docker.cnb.cool`, 服务器拉的是这个制品库; 两边同时部署会竞争推送。
镜像靠密钥仓库的 `github-sync.yml`(GITHUB_USERNAME / GITHUB_TOKEN); 没有它同步阶段会失败, 不会再静默跳过。

## 2. 部署只由 tag 触发, push 不部署

| 动作 | 发生什么 | 是否动生产 |
|---|---|---|
| 推分支 `git push cnb main` | 同步 GitHub 镜像 + 构建 capable 验证 | ❌ 不动 |
| 推 tag `git push cnb v0.2.0` | 构建两档 → 推 `:latest`/`:slim` + `:v0.2.0`/`:v0.2.0-slim` → SSH 部署 | ✅ 动 |

- push 阶段只构建 capable: `slim` 就是 base 加空行, capable 能过则 slim 必过。
- `.cnb.yml` 里 `main: push:` 只允许 build + sync; 绝不能引用 `dsh-deploy.yml`。
- 部署脚本会 `up -d --force-recreate`: 方向目录是挂载的, 只改清单时镜像不变,
  不强制重建容器就不会重跑 plan-boot。
- tag 流水线会 import 密钥仓库的 `dsh-deploy.yml` 和 `github-sync.yml`; 两者的
  `allow_events` 必须含 `tag_push`, `allow_branches` 必须含 `v*`(tag 事件的
  `CNB_BRANCH` 是 tag 名)。否则 Prepare 阶段直接失败, 不会构建也不会部署。
- 不要为了"让它部署"而在 push 阶段偷偷加 deploy; 也不要给每个 push 自动打 tag。

## 3. 三层结构: 镜像 = 环境, 方向 = 数据, 实例 = 隔离

| 层 | 在哪 | 改它要做什么 |
|---|---|---|
| 环境 | `Dockerfile`(两档: slim/capable) | 重建镜像 + 打 tag |
| 方向 | `plans/<方向>/`(compose 挂载) | `git pull` + 重启容器, 不重建镜像 |
| 实例 | `docker-compose.yml` / `docker-compose.dev.yml` | `git pull` + `up -d` |
| 启动逻辑 | `entrypoint.sh` / `scripts/plan-boot.sh` | 重建镜像 + tag |
| 状态 | named volumes | 不动 |

- **镜像只装环境**: 方向清单不烤进镜像(`COPY plans/` 已删); 改清单不用重建。
- **开发实例是第二个 compose 栈**, 不是第二个镜像: project `harness-dev`、卷 `dsh-dev-*`、端口 3211。
- **开发实例默认用 base 档(`:slim`)**: 迭代要快, 大多数插件用不到 LibreOffice/Python/CJK。
  某个插件确实需要系统依赖时改 `plans/dev/plan.env` 的 `PLAN_ENV`, 并写下是哪个插件要的 ——
  那是「环境变了」, 该走重建镜像那条路。
- **方向选择写在 `.env`**(`DSH_PLAN` / `DSH_IMAGE`): `up.sh` 写, deploy 的 `docker compose up -d` 读;
  否则会打回默认 `full` / `:latest`。
- 判定口诀: **环境进镜像, 方向进挂载, 状态进卷; 只有环境变了才重建。**

## 4. 开发实例只服务于插件作者本人

| 链路 | 文件 | 适用对象 | 改代码要做什么 |
|---|---|---|---|
| 发布链路 | `plans/<方向>/plugins.txt` | 所有人 | 改清单 + git pull + 重启容器(不用发版/重建) |
| 开发链路 | `docker-compose.dev.yml` + `bootstrap-dev/` | **只有插件作者本人** | 同步构建产物 + 重启开发实例 |

**目录约定**: 一个插件一个子目录, 不是把所有插件塞进同一个路径。

```
/srv/dev-plugins/                 <- 宿主根目录 (DSH_DEV_PLUGINS, 挂到 /opt/dev-plugins)
  ├── dsh-workspace-mesh/         <- 每个子目录是一个完整可加载的包
  │     ├── package.json          <- 必须有; name 决定装成什么
  │     ├── cordis.patch.yml      <- 有 dsh.bundle 时自动被组合
  │     └── <入口文件>            <- 必须已构建; 按 package.json 的 exports["."] / main 解析, 不强制叫 lib/index.js
  └── dsh-another-plugin/
```

- **link 只适用于零运行时依赖的包**: pnpm 的 `link:` 只建符号链接, **不会给被链接的目录装依赖**,
  被链接的包在运行时 require 自己的 dependency 会 `MODULE_NOT_FOUND`。有 `dependencies` 的包先
  `pnpm pack`, 再用 `dsh plugin --profile web add /abs/path/<包>-<版本>.tgz` 装(同样不用发版)。
- `sudo bash ./scripts/up.sh dev` 起开发实例（仓库里的 `scripts/*.sh` 没带可执行位，直接 `./scripts/up.sh` 会 `Permission denied`）；`scripts/sync-plugin.ps1 -Plugin <目录名>` 同步并重启。
- 开发实例失败不自动拉起(`restart: "no"`), 便于看日志。
- 不要把开发实例的挂载/脚本挪进生产栈; 使用者没有源码, 他们改 `plans/<方向>/plugins.txt`
  或在网页插件管理器里装。

### 4.1 服务器只运行, 不构建

**任何一台部署机(开发实例所在的那台也一样)都不是构建机。** 上面只跑容器; `pnpm install` /
`pnpm build` / 测试套件都在本地跑完再同步。理由不是洁癖: 这些机器的内存是给运行时留的,
一个插件的开发依赖(数百个包、数百 MB)足以把可用内存压到 0。

- 2026-11-03 的实例: 有人把插件仓库 clone 到一台 **1.6 GB** 的运行机上直接 `pnpm install`,
  十分钟内内存被打穿, 系统卡死并被云监控硬重启 —— 日志里只有 journald 的 `Under memory
  pressure`, 连 OOM killer 都没写出来; 那台机上还跑着 10 个容器和 dsh 本身。
- 要验证"在真实宿主上能装": 本地 `pnpm pack` 出 tgz, scp 上去, 容器里
  `dsh plugin --profile <profile> add /abs/path/<包>.tgz`。打包在本地, 服务器只解包和链接。
- 要跑完整 Linux 测试矩阵: 交给 CI, 或临时开一台内存够的实例; 不要借用部署机。
- 收工要还原: `20-link-plugins.sh` 只增不删, 从 `/srv/dev-plugins/` 删目录不会把 link 从
  profile 里摘掉 —— 必须 `dsh plugin --profile <profile> remove <包名>`, 再重启实例。
## 5. 不暴露个人信息与凭据

- **不写具体主机地址**。远端用 SSH 别名(例如 `dsh-server`), 地址只存在本机 `~/.ssh/config`。
- **不在仓库里放密钥**。CNB 没有 GitLab 的 `from_secret`; 敏感值放**密钥仓库**, 用 `imports` 注入。
  密钥仓库禁止 clone 与本地 push, 只能 Web 编辑。文件里用 `allow_slugs` / `allow_branches` /
  `allow_events` 声明最小可引用范围。
- 宿主机路径用环境变量传(`DSH_DEV_PLUGINS`), 默认值是服务器侧通用路径。

## 6. 改动的影响面

| 改了什么 | 需要重建镜像? | 需要打 tag 才上线? |
|---|---|---|
| `plans/**`(方向 / 插件清单) | **否**(挂载) | 是(或手动 git pull + force-recreate) |
| `docker-compose.yml` / `docker-compose.dev.yml` | 否 | 是 |
| `entrypoint.sh` / `scripts/plan-boot.sh` | **是** | 是 |
| `bootstrap-dev/**` / `scripts/sync-plugin.ps1` | 否 | 否(只影响开发实例) |
| `Dockerfile` | **是** | 是 |
| `.cnb.yml` / `deploy/*.sh` | 否 | 是(改 `dsh-deploy.sh` 还要同步服务器 `~/bin/`) |
| `docs/*` / `README*` / `AGENT.md` | 否 | 否(只推分支即可) |

## 7. 机制备忘(改之前先懂)

- **方向目录是挂载的**: 改 `plans/**` 后要 `up -d --force-recreate`(或 `restart dsh`),
  镜像不变时 compose 不会自己重启。
- **计划级 patch**: `plans/<方向>/patch.yml` 由 plan-boot 以 `dsh --patch` 叠在 profile 层之后，用于挂载 bundle patch 为空的插件（如 mesh）和非私有默认值；加载前先 `--dump-config` 验证，失败只 WARN 不阻断启动。
- **plan-boot 按 diff 装插件**: 它把当前清单和上次成功应用的 `.plan-<方向>.applied` 比较,
  只 add 新增/变更的行, 没变的跳过; 从清单删掉的行只提示不卸载。所以改一行清单只会装那一行,
  不会整份重装。
- **`dsh plugin --profile <p> add <spec>`** 在 profile 目录跑 pnpm; npm 包必须写
  `name@version`(写成 `name version` 会生成非法依赖名, 之后该 profile 的所有
  pnpm 安装都会失败); git 写 `github:owner/repo#sha`; 本地源码写 `link:/abs/path`。
- pnpm 跑完后 DSH 会 reconcile: 新装的包若声明 `dsh.bundle`(自带 `cordis.patch.yml`),
  会写进 `dsh.profile.bundles` 并组合出对应行, 插件随之挂载。
- **compose 会插值 `$VAR`**: 只要还在 compose 里写 shell, 变量就必须写 `$$VAR`。
- **shipped profile 是懒创建的**: `/data/dsh-home/profiles/<name>` 第一次被 `dsh --profile ...`
  引用时才落地。装插件前必须先跑一次 `dsh --profile <name> --dump-config`;
  `bootstrap-dev` 也先 materialize。
- **`assignmentFile`** 这类相对路径相对**宿主进程 cwd** 解析, 容器里是 `/data/workspace`。
- **`dsh plugin` 依赖 PATH 上的 pnpm**; 镜像里没有会报 `pnpm was not found`(Dockerfile 已装 pnpm@11)。
- **流水线 success ≠ 已部署**: 部署阶段必须看日志里有没有 `[deploy] ps`。
- **开发实例与生产共用镜像, 但卷/端口/项目名独立**; 不要用普通 `docker compose up` 起
  `dev` 方向(会落到生产栈)。

## 8. 提交前自查

- [ ] 仓库里没有 IP、域名、用户名、密钥、私有仓库地址
- [ ] 没有改动标准部署的行为(别人 clone 下来应当开箱即用)
- [ ] 新的可选能力都在明确的 opt-in 开关后面(环境变量或单独的 compose 文件)
- [ ] 没有把 `bootstrap-dev/` 或开发实例的东西挪进生产栈
- [ ] 改 `plans/**` 没有顺手改 Dockerfile(不需要重建)
- [ ] 涉及 CI 的改动: 部署只在 `tag_push` 里, push 阶段不部署; 缺变量时**失败**而不是静默跳过
