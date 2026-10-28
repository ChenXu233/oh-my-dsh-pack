# 安装方案（plans）

同一个镜像，多种装法。`plans/<方案>/` 决定"装什么、怎么起"，镜像只提供两档系统依赖。

---

## 1. 五档方案

| 方案 | 给谁 | 镜像 | 入口 | 预装 |
|---|---|---|---|---|
| `full` | 作者本人 / 想要完整体验的人 | capable | web 常驻 | `plans/full/plugins.txt`（全部风味） |
| `mini` | 只要一个能用的 dsh | slim | web 常驻 | 无 |
| `chat` | 打开就聊 | slim | web 常驻 | 记忆 / 思考档位 / 富文本 / 生图 / 通知 |
| `harness` | 要"能出东西"：文档、表格、PPT、图片、联网研究、定时任务 | capable | web 常驻 | 能力类插件 + office 技能 |
| `coder` | 无头编程器，一次性任务 | slim | headless | 默认无 |

`full` 是默认值：`DSH_PLAN` 不设时就是它。

---

## 2. 怎么用

```bash
./scripts/up.sh              # full
./scripts/up.sh mini
./scripts/up.sh harness
DSH_MEM_LIMIT=4g ./scripts/up.sh harness   # capable 档要跑 LibreOffice，内存给够

# 无头编程器：一次任务，结果走 stdout
./scripts/up.sh coder "把测试修好"
echo "总结这个仓库" | docker compose run --rm -T -e DSH_PLAN=coder dsh
```

`up.sh` 读 `plan.env` 里的 `PLAN_TIER` 自动选镜像 tag：

| PLAN_TIER | 镜像 tag |
|---|---|
| `capable` | `:latest` |
| `slim` | `:slim` |

想钉死版本：`DSH_IMAGE=docker.cnb.cool/chenxu233/oh-my-dsh-pack:v0.1.0 ./scripts/up.sh full`。

---

## 3. 一个方案由什么组成

```
plans/<方案>/
  plan.env      # 元信息 + 用哪个 profile + 怎么起
  plugins.txt   # 预装插件，每行一个 spec（可写行尾注释）
```

`plan.env` 只有四个有效字段：

| 字段 | 取值 | 作用 |
|---|---|---|
| `PLAN_TIER` | `slim` / `capable` | 选镜像档位，`up.sh` 据此挑 tag |
| `PLAN_PROFILE` | `web` / `headless` | 起 dsh 的哪个 profile |
| `PLAN_ENTRY` | `web` / `headless` | 常驻服务，还是一次性任务 |
| `PLAN_TITLE` / `PLAN_DESC` | 字符串 | 只用于展示 |

`plugins.txt` 的每行会交给 `dsh plugin --profile <profile> add`，支持 npm 包名、
`github:owner/repo#sha`、`link:/abs/path`。装失败只 WARN，不阻断启动。

启动链路只有一条：

```
docker compose up -d
  └─ /opt/entrypoint.sh          # 跑 bootstrap/ 与 dev/ 里的 .sh
       └─ /opt/scripts/plan-boot.sh
            ├─ source plans/$DSH_PLAN/plan.env
            ├─ dsh --profile <p> --dump-config    # 先让 profile 落地
            ├─ dsh plugin add ...                 # 按 plugins.txt 装（清单没变就跳过）
            └─ exec dsh --profile <p> ...         # web 或 headless
```

> **旧版的坑（已修）**：原来的 `bootstrap/10-plugins.sh` 在 dsh 首次启动**之前**跑，
> 那时 `$DSH_HOME/profiles/web` 还不存在，脚本直接 skip——插件要等第二次启动才装上。
> 现在 `plan-boot.sh` 先用 `--dump-config` 把 profile 材料化，再装插件。

---

## 4. 镜像两档：为什么必须分

| 能力 | 靠什么 | 在哪个档 |
|---|---|---|
| 对话 / 代码 / 终端 | dsh 本体 | 两档都有 |
| 文档、表格、PPT | `office-*` 技能 → python-docx/pptx/openpyxl | capable |
| 渲染、PDF 导出、公式重算 | LibreOffice | capable |
| 中文排版不串 | fonts-noto-cjk | capable |
| 视频合成、真实浏览器 | ffmpeg / chromium | **预留**（默认不装） |

capable 会比 slim 大 1G 左右。只想聊天的人不该为 LibreOffice 付这个代价，所以分档。

### 预留位：视频 / 浏览器

```bash
# 视频生成所需的系统依赖（插件侧生态已有，镜像侧先预留）
docker build --target capable --build-arg INSTALL_FFMPEG=1 -t ... .
# 需要真实浏览器的抓取 / 自动化
docker build --target capable --build-arg INSTALL_CHROMIUM=1 -t ... .
```

对应地在 `plans/harness/plugins.txt` 末尾打开注释即可，现在不启用。

---

## 5. 换方案会发生什么

- **会话不丢**：`full`/`mini`/`chat`/`harness` 共用 `web` profile，历史记录、API Key、设置都在同一个卷里。
- **插件只增不减**：`plan-boot.sh` 只会 `add`，不会删已装的包。先 `full` 后 `mini`，
  full 的插件仍然挂着。
- **要真按方案重来**：删掉 profile 再起（会丢会话历史）：

  ```bash
  # 只清空（不启动），然后重新 up
  docker compose run --rm -e DSH_PLAN_RESET=1 -e DSH_PLAN_RESET_ONLY=1 dsh
  ./scripts/up.sh
  ```

- **`coder` 单独**：headless 用独立的 `headless` profile，不跟 web 共用历史。

---

## 6. 加一个方案

1. `mkdir -p plans/<名字>`，写 `plan.env`（四个字段）和可选的 `plugins.txt`
2. `./scripts/up.sh <名字>`
3. 需要新系统依赖时改 `Dockerfile` 的 capable 阶段（会重建镜像）

不需要改 compose、entrypoint、CI。

---

## 7. 还没做的

| 项 | 说明 |
|---|---|
| `chat` 真正关掉编码工具 | 现在只是"不主动装"；要在 profile 层关 bundle 得加 patch 覆盖层 |
| 视频生成 | 镜像位预留了 ffmpeg，插件侧等生态或自己写 |
| capable 档实测 | LibreOffice 渲染链路要在容器里跑一遍（做份 PPT → 导出 PDF → 看中文）再算数 |
| 多用户 / 配额 | 不做。这是单人自托管，额度在模型网关那边管 |
