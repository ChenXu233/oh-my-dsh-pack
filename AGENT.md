# AGENT.md

给在本仓库里干活的 AI agent 和人类看的约定。先读索引, 再改任何东西。

## 0. 索引

| 位置 | 是什么 | 什么时候读 |
|---|---|---|
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | **开发指南(唯一入口)**: 部署、迭代、开发插件、配密钥、排错 | 任何要动手的改动之前 |
| [README.md](README.md) / [README.zh.md](README.zh.md) | 对外安装说明、目录说明 | 对外介绍 / 首次部署 |
| `.cnb.yml` | CNB 流水线: build → push 镜像 → SSH 部署 | 改 CI 或部署方式 |
| `deploy/dsh-deploy.sh` | 服务器端部署脚本(被受限 key 强制调用) | 改部署步骤 |
| `deploy/install.sh` | 服务器端手工一键部署/更新 | 手工上线 |
| `bootstrap/10-plugins.sh` | 发布链路: 预装 npm 包(进镜像) | 要加长期依赖的插件 |
| `bootstrap-dev/20-link-plugins.sh` | 开发链路: 把源码以 `link:` 装进 profile(不进镜像) | 开发自己的插件 |
| `docker-compose.dev.yml` | 开发覆盖层(挂载源码 + dev 脚本), 需显式 `-f` | 开发自己的插件 |
| `scripts/sync-mesh.ps1` | 本地 build → scp → 远端重启 | 每轮迭代 |
| `Dockerfile` | node22 + dsh + pnpm, 改它必须重建镜像 | 改运行环境 |

## 1. 主仓库是 CNB, GitHub 不参与

**规矩: 提交后只推 CNB(`git push cnb main`), 不要推 GitHub。**

| 远端 | 角色 | 说明 |
|---|---|---|
| `cnb` (`cnb.cool/ChenXu233/oh-my-dsh-pack`) | **唯一真源** | 镜像在这里构建, 流水线在这里跑 |
| `origin` (GitHub) | 历史遗留, 不参与 | 同步阶段已删除, 服务器也不再从它拉 |

理由: 镜像由 CNB 构建并推到 `docker.cnb.cool`, 服务器拉的是这个制品库; 两边同时部署会竞争推送。
所以 GitHub 不镜像、不部署, 避免出现两个真相。

动作序列: 改文件 → 本地 commit → `git push cnb main` → 等流水线(build image → push image → deploy)。
**不要执行 `git push origin`。** 远端 URL 里也不要内嵌 token, 用 credential helper 或 `.netrc`。

服务器上的 `~/harness-deploy` 的 `origin` 已指向 CNB(`https://cnb.cool/ChenXu233/oh-my-dsh-pack.git`),
上游为 `origin/main`。

## 2. "免发布迭代"链路只服务于插件作者本人

| 链路 | 文件 | 适用对象 | 改代码要做什么 |
|---|---|---|---|
| 发布链路 | `bootstrap/10-plugins.sh` 的 `PLUGINS` 列表 | 所有人 | 发一个 npm 版本 + 重建镜像 |
| 开发链路 | `bootstrap-dev/20-link-plugins.sh` + `docker-compose.dev.yml` | **只有插件作者本人** | 同步构建产物 + 重启容器 |

开发链路的前提是"你手上有这份插件的源码"。仓库的使用者没有这份源码, 他们应该:

- 要插件 → 改 `bootstrap/10-plugins.sh` 的 `PLUGINS` 列表, 填 npm 包名; 或者启动后在网页插件管理器里装。
- 不要照抄 `docker-compose.dev.yml` 的挂载。挂空目录进去只会在日志里留一句 `[dev] skip`。
- 不要把 `bootstrap-dev/` 当成必需组件, 删掉不影响标准部署。

## 3. 不暴露个人信息与凭据

- **不写具体主机地址**。远端用 SSH 别名(例如 `dsh-server`), 地址只存在本机 `~/.ssh/config`。
- **不在仓库里放密钥**。CNB 没有 GitLab 的 `from_secret`; 敏感值必须放**密钥仓库**, 用 `imports` 注入。
  密钥仓库禁止 clone 与本地 push, 只能 Web 编辑, 这正是它的安全价值。
  文件里用 `allow_slugs` / `allow_branches` / `allow_events` 声明最小可引用范围。
- 宿主机路径用环境变量传(`DSH_MESH_SRC`), 默认值是服务器侧通用路径。

## 4. 改动的影响面

| 改了什么 | 需要重建镜像? | 需要 push 后等流水线? |
|---|---|---|
| `bootstrap/*.sh` | **是** | 是 |
| `bootstrap-dev/*.sh` | 否 | 是(`up -d` 即生效) |
| `docker-compose.yml` / `docker-compose.dev.yml` | 否 | 是 |
| `Dockerfile` | **是** | 是 |
| `.cnb.yml` / `deploy/*.sh` | 否 | 是(下次部署生效) |
| `docs/*` / `README*` / `AGENT.md` | 否 | 否 |

判定口诀: **在 `/opt/bootstrap` 里的跟镜像走, 在 `/opt/dev` 里的跟仓库走。**

## 5. 机制备忘(改之前先懂)

- `dsh plugin --profile web add <spec>` 在 profile 目录跑 pnpm。spec 可以是 npm 包名、git 地址、tarball,
  或 `link:/abs/path`、`file:/abs/path`。
- pnpm 跑完后 DSH 会 reconcile: 新装的包若声明 `dsh.bundle`(自带 `cordis.patch.yml`), 会写进
  `dsh.profile.bundles` 并组合出对应行, 插件随之挂载。所以 `link:` 安装能生效, 不用手工改 profile。
- **compose 会插值 `$VAR`**: entrypoint 里的 shell 变量必须写 `$$VAR`, 否则会被替换成空字符串。
  历史上就是因为这个, `bootstrap/` 与 `bootstrap-dev/` 的脚本一直空转。
- `assignmentFile` 这类相对路径相对**宿主进程 cwd** 解析, 容器里是 `/data/workspace`。
- `dsh plugin` 依赖 PATH 上的 pnpm; 镜像里没有就会报 `pnpm was not found`(Dockerfile 已装 pnpm@11)。
- **流水线 success ≠ 已部署**: 部署阶段必须看日志里有没有 `[deploy] ps` 的输出。

## 6. 提交前自查

- [ ] 仓库里没有 IP、域名、用户名、密钥、私有仓库地址
- [ ] 没有改动标准部署的行为(别人 clone 下来应当开箱即用)
- [ ] 新的可选能力都在明确的 opt-in 开关后面(环境变量或单独的 compose 覆盖层)
- [ ] 没有把 `bootstrap-dev/` 里的东西挪进 `bootstrap/`
- [ ] 涉及 CI 的改动, 确认缺变量时会**失败**而不是静默跳过
