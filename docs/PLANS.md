# 方向（plans）

一个镜像只装**环境**；方向是**数据**，运行时由 `scripts/plan-boot.sh` 装插件并起服务。
方向目录由 compose 挂载进容器（`./plans:/opt/plans:ro`），**改清单不需要重建镜像**。

## 矩阵

| 方向 | 环境 | 镜像 tag | profile | 入口 | 预装 | 实例 |
|---|---|---|---|---|---|---|
| `full` | capable | `:latest` | web | web | 30（作者口味） | 生产（默认） |
| `chat` | base | `:slim` | web | web | 待选 | 按需 |
| `harness` | capable | `:latest` | web | web | 待选 | 按需 |
| `dev` | base | `:slim` | web | web | 0（空白） | 开发实例 |

- `full` 是默认方向：`DSH_PLAN` 不设时用它。
- `chat` / `harness` 的清单先留空，选好插件后写进 `plugins.txt` 即可，不用重建镜像。
- `dev` 只给 `docker-compose.dev.yml` 用：空白 dsh + `bootstrap-dev` 把源码 `link:` 进来。
- 环境只有两类：`base`（node + dsh + pnpm + git）和 `capable`（+ Python / LibreOffice / CJK）。
  只有系统依赖不同才需要新镜像；方向不产生镜像。

## 一个方向由什么组成

```
plans/<方向>/
  plan.env      # PLAN_ENV / PLAN_PROFILE / PLAN_ENTRY + 标题
  plugins.txt   # 每行一个 spec；# 注释
```

`plan.env` 的有效字段：

| 字段 | 取值 | 作用 |
|---|---|---|
| `PLAN_ENV` | `base` / `capable` | `up.sh` 据此选镜像 tag（`:slim` / `:latest`） |
| `PLAN_PROFILE` | `web` / `headless` | 起 dsh 的哪个 profile |
| `PLAN_ENTRY` | `web` / `headless` | 常驻 web，还是一次性任务 |
| `PLAN_TITLE` / `PLAN_DESC` | 字符串 | 只用于展示 |

`plugins.txt` 的每行交给 `dsh plugin --profile <profile> add`：npm 包写
`name@version`（**不要写空格**，`name version` 会变成非法包名）、git 写
`github:owner/repo#sha`、本地源码写 `link:/abs/path`。装失败只 WARN，不阻断启动。

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
                      └─ exec dsh --profile <p> ...        # web 或 headless
```

> 方向选择写进 `.env`：之后部署脚本的 `docker compose up -d` 会读它，
> 不会被打回默认 `full` / `:latest`。

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
