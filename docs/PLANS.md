# 方向（plans）

一个镜像只装**环境**；方向是**数据**，运行时由 `scripts/plan-boot.sh` 装插件并起服务。
方向目录由 compose 挂载进容器（`./plans:/opt/plans:ro`），**改清单不需要重建镜像**。

## 矩阵

| 方向 | 环境 | 镜像 tag | profile | 入口 | 预装 | 实例 |
|---|---|---|---|---|---|---|
| `full` | capable | `:latest` | web | web | 24（作者口味） | 生产（默认） |
| `chat` | base | `:slim` | web | web | 待选 | 按需 |
| `harness` | capable | `:latest` | web | web | 待选 | 按需 |
| `dev` | base | `:slim` | web | web | 0（空白） | 开发实例 |
| `ci` | base（预置 profile） | `:ci` | headless | headless | 1（烤进镜像） | 一次性 CI 任务 |

- `full` 是默认方向：`DSH_PLAN` 不设时用它。
- `chat` / `harness` 的清单先留空，选好插件后写进 `plugins.txt` 即可，不用重建镜像。
- `dev` 只给 `docker-compose.dev.yml` 用：空白 dsh + `bootstrap-dev` 把源码 `link:` 进来。
- `ci` 走独立编排 `docker-compose.ci.yml`：headless 一次性任务，profile 在 `:ci` 镜像构建期就装好，
  启动时零 `dsh plugin add`；`DSH_HOME` 默认用匿名卷，`--rm` 即丢，不跨任务残留。
  要让多次任务复用已装好的 profile，在环境里设 `CI_DSH_HOME_VOLUME=dsh-ci-home`，compose 会改用具名卷。
- 环境只有两类：`base`（node + dsh + pnpm + git）和 `capable`（+ Python / LibreOffice / CJK）。
  只有系统依赖不同才需要新镜像；方向不产生镜像。

## 一个方向由什么组成

```
plans/<方向>/
  plan.env      # PLAN_ENV / PLAN_PROFILE / PLAN_ENTRY + 标题
  plugins.txt   # 每行一个 spec；# 注释
  patch.yml     # 可选：叠加在 profile 层之后（挂载空 bundle patch 的插件 / 非私有默认值）
  config/       # 可选：首启时拷进 $DSH_HOME 的配置文件（目标已存在就跳过）
```

`plan.env` 的有效字段：

| 字段 | 取值 | 作用 |
|---|---|---|
| `PLAN_ENV` | `base` / `capable` | `up.sh` 据此选镜像 tag（`:slim` / `:latest`） |
| `PLAN_PROFILE` | `web` / `headless` | 起 dsh 的哪个 profile |
| `PLAN_ENTRY` | `web` / `headless` | 常驻 web，还是一次性任务 |
| `PLAN_ARGS` | 字符串 | 仅 headless：固化 dsh 调用参数（如 `--json`），追加到每次 `exec dsh` 后面 |
| `PLAN_TITLE` / `PLAN_DESC` | 字符串 | 只用于展示 |

`plugins.txt` 的每行交给 `dsh plugin --profile <profile> add`：npm 包写
`name@version`（**不要写空格**，`name version` 会变成非法包名）、git 写
`github:owner/repo#sha`、本地源码写 `link:/abs/path`。装失败只 WARN，不阻断启动。

启动时 `plan-boot.sh` 会记住上次成功应用的清单（`.plan-<方向>.applied`），
只对**新增/变更**的行执行 `dsh plugin add`；没变的行跳过。从清单里删掉的行只提示、
不自动卸载（避免误删网页手装或 `link:` 的包）。

`link:` 有个硬边界：**pnpm 只建符号链接，不会给被链接的目录装依赖**。被链接的包在运行时
`require` 自己的 dependency 会 `MODULE_NOT_FOUND`，而且报错发生在加载插件时，看上去像
插件本身坏了。所以有 `dependencies` 的包不要走 `link:`，改成两行：

```bash
pnpm pack                                                       # 在该插件仓库里
dsh plugin --profile web add /abs/path/<包名>-<版本>.tgz          # 在开发容器里
```

tgz 一次改动要重打一次，但换来的是依赖真的被装上、和发布链路一致。

## 启动链路

```
./scripts/up.sh <方向>
  └─ 读 plan.env 选 tag，写 .env（DSH_PLAN / DSH_IMAGE）
       └─ docker compose up -d
            └─ /opt/entrypoint.sh
                 ├─ /opt/bootstrap/*.sh        # 镜像内初始化
                 ├─ /opt/dev/*.sh              # 只有开发实例挂载
                 └─ /opt/scripts/plan-boot.sh
                      ├─ source /opt/plans/<方向>/plan.env
                      ├─ dsh --profile <p> --dump-config   # profile 落地
                      ├─ dsh plugin add ...                # 按 plugins.txt 装
                      ├─ dsh --dump-config --patch ...     # 验证 patch.yml, 失败则跳过
                      ├─ cp config/* -> $DSH_HOME          # 仅首次, 不覆盖已有文件
                      └─ exec dsh --profile <p> ...        # web 或 headless
```

> 方向选择写进 `.env`：之后部署脚本的 `docker compose up -d` 会读它，
> 不会被打回默认 `full` / `:latest`。

## 插件配置初始化

三层，从低到高：

| 层 | 放什么 | 在哪 |
|---|---|---|
| 计划默认值 | 非私有、谁都能用的配置；空 bundle patch 插件的挂载行 | `plans/<方向>/patch.yml` |
| 插件自有文件 | mesh 的 peers/publicUrl（`$DSH_HOME/mesh-config.json`）、pet、task-board、workbuddy 等自己写的文件 | `plans/<方向>/config/` 首启落地，之后由插件/设置页维护 |
| 整机迁移 | 私有 provider、凭据、技能、会话、插件数据 | `dsh-config-manager` 导出 → 服务器导入 |

`patch.yml` 只放前两类里"非私有"的部分。私有值（provider baseURL/密钥、mesh 的 peer token 与 meshSecret、本机绝对路径）不进仓库。

私有配置走 `dsh-config-manager`：桌面端按分区勾选导出（settings / ui / providers / plugins / mcp / prompts / skills / agentPresets / agentInstructions / workspaces / secrets / pluginData / pluginFiles），服务器网页导入。**启动期不自动导入**——它的 CLI 只有 backup/verify/restore/snapshots，没有"应用某个 ZIP"的子命令，导入必须经过人工确认冲突与路径映射。

迁移步骤（`dsh-config-manager`）：

1. 桌面：设置 → 备份与迁移 → 导出，只勾要带的分区（`secrets` / `pluginFiles` 默认别带，后者可能含明文凭据）
2. 服务器：同一入口导入，冲突逐项决策；导入前它会自动备份当前配置，出错可回滚
3. `pluginData` 只收声明了 `dsh.dataDirs` 的插件（外加内置取证来源）；pet / task-board / image-gen / whale 这些没声明，不在任何分区里，迁移要手工拷 `$DSH_HOME/<目录>`

注意 `dsh-workspace-mesh`：0.3.3 在 dsh 0.2.2 上把 volatile 的 peers 直接当数组用，空配置会抛 `options.peers is not iterable`；所以 `plans/full/config/mesh-config.json` 里预置了 `{"peers": []}`。它的 `cordis.patch.yml` 是空数组，`dsh plugin add` 只装包不挂载，所以挂载行必须写在 `patch.yml` 里。它的 `publicUrl` / `hub` 只认 `mesh-config.json`，写进 patch 会被 schema 丢掉。

## CI 用法（ci 方向）

CI 的痛点不是"装哪些插件"，而是**每次冷启都装一遍**。ci 方向把这件事挪到镜像构建期：

```
构建期 (:ci 镜像)                      运行期 (每次 CI 任务)
  dsh --profile headless --dump-config    从 /opt/ci-profile 拷回 profile（毫秒）
  dsh plugin add agent-teams               exec dsh --profile headless --json <PLAN_ARGS 之外的参数>
  cp profile -> /opt/ci-profile            --rm 丢掉 DSH_HOME
```

### 构建与取镜像

```bash
# 打 tag 会自动构建并推送 :ci / :<tag>-ci（同时推 :latest/:slim 并部署）
git tag v0.2.0 && git push cnb v0.2.0

# 或：在 main 分支详情页点「构建 CI 制品包」按钮（web_trigger_ci_image，只推 :ci，不动生产）
# 本地没有 CI 环境时也能验：
docker pull docker.cnb.cool/chenxu233/oh-my-dsh-pack:ci
```

### 一次性跑一个任务

```bash
CI_WORKSPACE=$PWD DEEPSEEK_API_KEY=xxx \
  ./scripts/up.sh ci '写一个 bug 报告并写到 /data/workspace/report.md'
```

`up.sh ci` 会切到 `docker-compose.ci.yml`：

- 当前 checkout 挂到 `/data/workspace`，dsh 直接读写
- 不分配 TTY（`tty: false`），保住 `--json` 行流，`jq` 能逐行读
- 不发布端口、不挂 healthcheck、不留后台容器
- `PLAN_ARGS` 默认 `--json`；调调用方参数走 `./scripts/up.sh ci -a <AGENT> -w <WORKFLOW> "prompt"`

**profile 复用 / 冷启权衡**：默认匿名卷每次丢弃 DSH_HOME，从 `/opt/ci-profile` 拷回（纯本地 IO，毫秒级）。
若 profile 变大、连拷贝都想省，设 `CI_DSH_HOME_VOLUME=dsh-ci-home` 改用具名卷，第一次之后目录已存在，
`plan-boot` 连拷都不做。代价是会话历史等状态会跨任务残留；CI 场景通常更在意隔离，默认保持匿名卷。

### headless 的两个坑（CI 必读）

1. **沙箱在容器里不可用，而且失败是静默的。** 内核没开 landlock / bwrap namespace 被拒时，
   `workspace-write` 会让所有 bash 工具失败，但进程仍然 `exit 0`、输出 `final: done`。
   ci 方向在 `plan.env` 里直接 `export DSH_PERMISSION_MODE=danger-full-access` +
   `DSH_APPROVAL_POLICY=never`：容器本身就是边界，没有人能点确认。
2. **slash 命令在 headless 不执行。** `dsh headless "/review"` 里的 `/review` 是当普通用户消息
   递进去的，不走 composer 的 command runtime。**所有靠 slash 命令暴露能力的插件在 CI 里等于没装。**
   实测 headless 基线 24 个工具，只有 `@chenxu233/dsh-agent-teams` 会真加工具（+15），
   已预置进 `:ci` 镜像；`dsh-gemini-tool-schema` 往 stdout 打印、污染 `--json` 流，别装。

> 退出码：工具失败当前不会改变 dsh 的退出码。CI 要判失败，用仓库自带的
> `scripts/ci-run.sh`，它跑完会扫 `--json` 流里的 `tool_result.status=error`，
> 有 error 就 exit 1；没用这个薄壳就得自己解析。

## 加一个方向

1. `mkdir -p plans/<名字>`，写 `plan.env` 和可选的 `plugins.txt`
2. `./scripts/up.sh <名字>`
3. 需要新系统依赖时才改 `Dockerfile`（会重建镜像）；只改清单不用。

## 切方向

- **插件只增不减**：`plan-boot.sh` 只 `add`，不删已装的包。先 `full` 后 `chat`，
  full 的插件仍然挂着。
- 要干净重来（会丢会话历史）：

  ```bash
  docker compose run --rm -e DSH_PLAN_RESET=1 -e DSH_PLAN_RESET_ONLY=1 dsh
  ./scripts/up.sh <方向>
  ```
