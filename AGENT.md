# AGENT.md

给在本仓库里干活的 AI agent 和人类看的约定。先读索引, 再改任何东西。

## 0. 索引

| 位置 | 是什么 | 什么时候读 |
|---|---|---|
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | **开发指南(唯一入口)**: 部署、迭代、开发插件、配密钥、排错 | 任何要动手的改动之前 |
| [README.md](README.md) / [README.zh.md](README.zh.md) | 对外安装说明、目录说明 | 对外介绍 / 首次部署 |
| `.cnb.yml` | CNB 流水线: push 只验证; tag 才构建+推镜像+部署 | 改 CI 或部署方式 |
| `deploy/dsh-deploy.sh` | 服务器端部署脚本(被受限 key 强制调用) | 改部署步骤 |
| `deploy/install.sh` | 服务器端手工一键部署/更新 | 手工上线 |
| [docs/PLANS.md](docs/PLANS.md) | **安装方案**: 五档各是什么、怎么加方案、镜像为什么分两档 | 改方案 / 加方案 / 动镜像档位 |
| `plans/<方案>/plan.env` + `plugins.txt` | 发布链路: 一个方案装什么、怎么起(进镜像) | 要加长期依赖的插件 / 新增方案 |
| `bootstrap-dev/20-link-plugins.sh` | 开发链路: 遍历 `/opt/dev-plugins/<插件>/` 逐个 `link:` 装进 profile(不进镜像) | 开发自己的插件 |
| `docker-compose.dev.yml` | 开发覆盖层: 挂载多插件根目录 `/srv/dev-plugins` + dev 脚本, 需显式 `-f` | 开发自己的插件 |
| `scripts/sync-plugin.ps1` | 本地 build → scp → 远端重启(`-Plugin <插件名>`) | 每轮迭代 |
| §3.1 | **环境归属**: 配套实例只属于维护者本人, 别人的环境各自独立 | 第一次同步插件之前 |
| §7 | **插件原生设置页**: `settings.section` + `/api` 已认证数据面的接法 | 要给插件加设置页 |
| `Dockerfile` | node22 + dsh + pnpm; 两档构建(`slim` / `capable`), 改它必须重建镜像 | 改运行环境 / 加系统依赖 |

## 1. 主仓库是 CNB, GitHub 只是镜像

**规矩: 提交后只推 CNB(`git push cnb main`), 不要推 GitHub。**
GitHub 是流水线用 `tencentcom/git-sync` 推过去的镜像, 手工往 GitHub 推会和流水线抢同一个 ref。

| 远端 | 角色 | 说明 |
|---|---|---|
| `cnb` (`cnb.cool/ChenXu233/oh-my-dsh-pack`) | **唯一真源** | 镜像在这里构建, 流水线在这里跑 |
| `origin` (GitHub) | 只读镜像 | 由 `main.push` / tag 流水线推过去; 不参与构建、部署, 服务器也不从它拉 |

理由: 镜像由 CNB 构建并推到 `docker.cnb.cool`, 服务器拉的是这个制品库; 两边同时部署会竞争推送。
所以 GitHub 只做镜像、不做部署, 避免出现两个真相。远端 URL 里也不要内嵌 token。
镜像靠密钥仓库的 `github-sync.yml`(GITHUB_USERNAME / GITHUB_TOKEN); 没有它同步阶段会失败, 不会再静默跳过。

服务器上的 `~/harness-deploy` 的 `origin` 已指向 CNB(`https://cnb.cool/ChenXu233/oh-my-dsh-pack.git`),
上游为 `origin/main`。

## 2. 部署只由 tag 触发, push 不部署

这是硬规矩, 改 CI 时必须守住。

| 动作 | 发生什么 | 是否动生产 |
|---|---|---|
| 推分支 `git push cnb main` | build 两档做验证 + 同步 GitHub 镜像 | ❌ 不动 |
| 推 tag `git push cnb v0.1.0` | build 两档 → push `:latest`/`:slim` + `:v0.1.0`/`:v0.1.0-slim` → SSH 部署 | ✅ 动 |

- `.cnb.yml` 里 `main: push:` 只有 build + sync 两个阶段。sync **只允许**引用 `github-sync.yml`(仅同步凭据),
  绝不能引用 `dsh-deploy.yml`; `"v*": tag_push:` 才 `imports` 部署密钥并部署。
- tag 名同时作为镜像 tag, 回滚时可以直接指到具体版本。
- 想上线时: `git tag v0.1.0 && git push cnb v0.1.0`。
- **不要**为了"让它部署"而在 push 阶段偷偷加 deploy; 也不要给每个 push 自动打 tag。
- 若希望 push 完全不触发流水线, 删掉 `main.push` 整段即可(那是唯一的"验证型"用途)。

## 3. "免发布迭代"链路只服务于插件作者本人

| 链路 | 文件 | 适用对象 | 改代码要做什么 |
|---|---|---|---|
| 发布链路 | `plans/<方案>/plugins.txt` | 所有人 | 发一个 npm 版本 + 重建镜像 |
| 开发链路 | `bootstrap-dev/20-link-plugins.sh` + `docker-compose.dev.yml` | **只有插件作者本人** | 同步构建产物 + 重启容器 |

**目录约定(不要搞错)**: 一个插件一个子目录, 不是把所有插件塞进同一个路径。

```
/srv/dev-plugins/                 <- 宿主根目录 (DSH_DEV_PLUGINS, 挂到 /opt/dev-plugins)
  ├── dsh-workspace-mesh/         <- 每个子目录是一个完整可加载的包
  │     ├── package.json          <- 必须有; name 决定装成什么
  │     ├── cordis.patch.yml      <- 有 dsh.bundle 时自动被组合
  │     └── lib/index.js          <- 必须已构建
  └── dsh-another-plugin/
```

- 早期版本把路径写死成 `/opt/mesh`, 只能放一个插件; 现在是遍历子目录, 加插件只加目录。
- 不要把两个插件塞进同一个目录: 包按 `package.json` 的 `name` 区分, 混在一起装不上。
- 每个插件用 `scripts/sync-plugin.ps1 -Plugin <目录名>` 同步, 互不干扰。

开发链路的前提是"你手上有这份插件的源码"。使用者没有这份源码, 他们应该改 `plans/<方案>/plugins.txt`,
或者启动后在网页插件管理器里装; 不要照抄 `docker-compose.dev.yml` 的挂载。

## 3.1 归属: 这是维护者自己的开发环境, 不是共享环境

**规矩: 本仓库配套的那台实例(SSH 别名 `dsh-server`, 维护者 ChenXu233 的个人机器)只属于维护者本人。**

- 它是**开发者自己的联调环境**: 维护者在这里跑部署、同步自己的插件、看自己的日志、做自己的实验。
  它不是公共测试机, 不是团队共享环境, 也不是"谁都可以往里推插件"的地方。
- **不是 ChenXu233 的开发者, 不需要也不应该**把自己的插件同步到这台机器上。
  仓库里也不会写这台机器的地址 —— 只有维护者本机的 `~/.ssh/config` 知道它指向哪。
- 其他开发者照样用这套 pack 和脚本开发, 但**机器、环境、数据卷都是各自的**:

  | 东西 | 维护者的 | 其他开发者应当怎样 |
  |---|---|---|
  | 服务器 | `dsh-server` 别名指向维护者自己的机器 | 用自己的服务器, 自己的 SSH 别名 |
  | 同步目标 | `scp` 到 `dsh-server` | `-SshHost <自己的别名>`, 或改本机 ssh config |
  | 插件根目录 | `/srv/dev-plugins`(`DSH_DEV_PLUGINS`) | 自己的目录, 环境变量传给 compose |
  | dsh-home / workspace 卷 | 维护者自己的 compose 卷 | 自己的卷(默认就是本机 compose 创建的) |
  | 访问入口 | 维护者自己的反代 + 自己的 token | 自己的入口、自己的 token |

- **脚本不绑定任何具体机器**: `scripts/sync-plugin.ps1`、`bootstrap-dev/20-link-plugins.sh`、
  `docker-compose.dev.yml` 只认环境变量与 SSH 别名。不要把别人的地址写进仓库或脚本默认值。
- 换句话说: **共享的是仓库里的脚本与文档, 不是运行环境。** 维护者在自己环境里做的实验
  (例如给某个插件加设置页) 不构成别人必须复刻的"环境", 别人只要复用同一套流程即可。

## 4. 不暴露个人信息与凭据

- **不写具体主机地址**。远端用 SSH 别名(例如 `dsh-server`), 地址只存在本机 `~/.ssh/config`。
- **不在仓库里放密钥**。CNB 没有 GitLab 的 `from_secret`; 敏感值放**密钥仓库**, 用 `imports` 注入。
  密钥仓库禁止 clone 与本地 push, 只能 Web 编辑。文件里用 `allow_slugs` / `allow_branches` /
  `allow_events` 声明最小可引用范围。
- 宿主机路径用环境变量传(`DSH_DEV_PLUGINS`), 默认值是服务器侧通用路径。

## 5. 改动的影响面

| 改了什么 | 需要重建镜像? | 需要打 tag 才上线? |
|---|---|---|
| `plans/**`(方案 / 插件清单) | **是** | 是 |
| `bootstrap/*.sh` | **是** | 是 |
| `bootstrap-dev/*.sh` | 否 | 否(服务器 `up -d` 即生效) |
| `docker-compose.yml` / `docker-compose.dev.yml` | 否 | 是 |
| `Dockerfile` | **是** | 是 |
| `.cnb.yml` / `deploy/*.sh` | 否 | 是 |
| `docs/*` / `README*` / `AGENT.md` | 否 | 否(只推分支即可) |

判定口诀: **在 `/opt/plans` 与 `/opt/bootstrap` 里的跟镜像走, 在 `/opt/dev` 里的跟仓库走。**

## 6. 机制备忘(改之前先懂)

- `dsh plugin --profile web add <spec>` 在 profile 目录跑 pnpm。spec 可以是 npm 包名、git 地址、tarball,
  或 `link:/abs/path`、`file:/abs/path`。
- pnpm 跑完后 DSH 会 reconcile: 新装的包若声明 `dsh.bundle`(自带 `cordis.patch.yml`), 会写进
  `dsh.profile.bundles` 并组合出对应行, 插件随之挂载。所以 `link:` 安装能生效。
- **compose 会插值 `$VAR`**: 只要还在 compose 里写 shell, 变量就必须写 `$$VAR`。
  历史上就是因此让 `bootstrap/` 与 `bootstrap-dev/` 的脚本一直空转。
  现在启动逻辑只在镜像里(`/opt/entrypoint.sh` → `/opt/scripts/plan-boot.sh`), compose 只传环境变量。
- **shipped profile 是懒创建的**: `/data/dsh-home/profiles/<name>` 第一次被 `dsh --profile ...` 引用时才落地。
  装插件前必须先跑一次 `dsh --profile <name> --dump-config`, 否则目录不存在 —— 旧版 bootstrap 就栽在这。
- `assignmentFile` 这类相对路径相对**宿主进程 cwd** 解析, 容器里是 `/data/workspace`。
- `dsh plugin` 依赖 PATH 上的 pnpm; 镜像里没有会报 `pnpm was not found`(Dockerfile 已装 pnpm@11)。
- **流水线 success ≠ 已部署**: 部署阶段必须看日志里有没有 `[deploy] ps`。

## 7. 给插件加一个原生设置页 (settings.section) + 已认证数据面

在 `dsh-workspace-mesh` 上实测跑通的接法 (2026-10, dsh 0.2.1-rc.3), 给别的插件加设置页照这个结构抄。
分两半: 浏览器半侧注册页面, 宿主半侧提供数据与写入。

### 7.1 浏览器半侧: 注册页面

- 包的 `package.json` 要有 `dsh.client = { platform: "web", inject: [...] }`,
  且 `inject` 里必须带 `@deepseek-ai/dsh-client-ui-settings`(没有它拿不到 settings 的 slots)。
- 浏览器半侧是一个普通的 client bundle: `client.js` 必须写成
  `window.__ModuleLoader__.load({ id: "<包名>", factory: (require) => { ... } })` 的惰性 CJS 形态,
  `package.json` 里用 `exports["./client"]` 指过去, 并把 `client` 放进 `files`。
- `client.js` 的 `apply(ctx)` 里:

  ```js
  ctx.slots.inject("settings.section", () => ctx.slots.register({
    name: "settings.section",
    id: "<插件命名空间>",
    order: 25,                      // 决定导航里排在哪
    label: () => "工作区网格",       // 字符串或函数; 函数每次取最新文案
  }, Component))
  ```

  **`settings.section` 没有条目所有权要求** —— 内置的"内置插件"页就是这样注册的,
  和 §6 里 config-editor 只认 `include` 子条目那堵墙无关。`id` 只用于去重与稳定 key。
- 组件拿不到 `t` / `renderSlot` 也能正常渲染; 需要双语就自己看 `document.documentElement.lang`。
- 样式对齐原生: `--dsw-alias-label-primary` / `--dsw-alias-label-tertiary` /
  `--dsw-alias-border-l1|l2` / `--dsw-alias-state-business-primary` / `--dsw-focus-ring-*`;
  标题 18px/600, 区块标题 15px/600, 正文 13px, 卡片 `.5px` 边框 + 8px 圆角。
  不要硬编码颜色, 也不要写全局选择器; 样式表按 `data-plugin-css` 去重注入。

### 7.2 数据面: 三条路只有一条通

| 方案 | 结果 |
|---|---|
| `ctx.remote.settings.describe()/mutate()` | ❌ 只投影 profile `include` 根下的条目; profile-patch 插入的条目没有 namespace, `namespaces` 里永远查不到它 |
| `TypertRemoteService`(`ctx.remote.<ns>`) | ❌ `link:` / `/srv/dev-plugins` 安装的插件目录没有 `node_modules`, `import "@deepseek-ai/dsh-typert-protocol"` 直接 `ERR_MODULE_NOT_FOUND` |
| `ctx.connection.fetch.register(...)` | ✅ 挂进 `/api` 之下, 自动继承 Host/Origin 围栏与浏览器 cookie 认证, 页面同源 `fetch()` 即可 |

宿主侧写法(和内置的 `/api/present.host`、`/api/changes.summary` 同一套):

```js
ctx.connection.fetch.register({
  path: "/api/<plugin>/state",      // 必须在 /api 下, 且方法不能重复
  methods: ["GET"],
  requestBody: "buffered",          // 另一个取值是 "streaming"
  fetch: async () => new Response(JSON.stringify(payload), {
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  }),
})
```

- **必须用非阻塞注入**: `ctx.inject(["connection"], (inner) => { ... })`。
  `apply()` 执行时 `ctx.get("connection")` 往往还没到 state 2, strict 读返回 undefined ——
  第一版就是栽在这, 日志是 `no connection.fetch service`, 页面全 404。
- 无 web 服务器的无头组合里没有 `connection`: 插件必须照常加载, 只打一行日志。

### 7.3 写配置: 插件自管一个覆盖文件

- 原生 settings 管道写不了(见 7.2), 所以配置写 `$DSH_HOME/<plugin>-config.json`,
  在 `apply()` 里读出来盖在 cordis 条目配置之上: **条目配置 → 覆盖文件 → 运行时配置**。
- 覆盖文件坏了只降级(打印 warn, 回落条目配置), 不能让 fiber 起不来 —— 起不来的 fiber 会让设置页整块消失。
- `POST /api/<plugin>/config` 要**先校验再落盘**: 类型/枚举/未知键逐项报错; 引用的文件(如
  `assignment.yml`)先试加载, 失败就 400 并带上路径, 不写半成品。
- 字段分两类并在响应里说清: "立即生效"(直接改内存里的 runtime 对象)与"重启生效"
  (落盘 + 返回 `pendingRestart`)。

### 7.4 迭代与验证顺序

1. `pnpm build && pnpm test`。新增路由/存储必须有 `node:test` 单测; 零依赖审计的允许列表要同步加
   `node:xxx`。
2. `scripts/sync-plugin.ps1 -Plugin <插件名> [-SkipBuild]` —— build → scp 到
   `/srv/dev-plugins/<插件>` → `compose up -d` + `restart dsh`。容器重启时
   `bootstrap-dev/20-link-plugins.sh` 重跑 `dsh plugin add link:...`, **client bundle 的 rev 只有这一步会变**,
   所以只改客户端代码也必须重启一次, 否则页面还拿旧 bundle。
3. 看日志确认: `[dev] linked: <插件>`、`[<ns>] ... route mounted at /api/...`。
4. 浏览器带 token 打开(日志末尾 `dsh web: https://<host>/?token=...`), 进 设置 → 新页面;
   保存一次配置, 再确认 `$DSH_HOME/<plugin>-config.json` 落盘、且重启后仍然生效。

### 7.5 踩过的坑

- `sync-plugin.ps1` 曾把 `client/client.js` scp 成插件根目录下的 `client.js`(相对路径被拍平);
  已改成按相对路径落盘并清理旧副本 —— 否则浏览器半侧永远加载不到。
- 客户端 bundle 语法错 = 整个插件不注册(页面显示"1 异常"): 提交前 `node --check client/client.js`。
- `plugins.detail.section` 会被宿主以 `subject === undefined` 再渲染一次(整页形态),
  组件这时必须返回自身, 不能返回 `null`。
- 页面里 `ctx.remote.settings` 想用, 基础 `"remote"` 也得在 `inject` 里, 否则是 undefined。

## 8. 提交前自查

- [ ] 仓库里没有 IP、域名、用户名、密钥、私有仓库地址
- [ ] 没有改动标准部署的行为(别人 clone 下来应当开箱即用)
- [ ] 新的可选能力都在明确的 opt-in 开关后面(环境变量或单独的 compose 覆盖层)
- [ ] 没有把 `bootstrap-dev/` 里的东西挪进 `bootstrap/`
- [ ] 涉及 CI 的改动: 部署只在 `tag_push` 里, push 阶段不部署; 缺变量时**失败**而不是静默跳过
- [ ] 没有把维护者自己的机器地址、目录或入口写进仓库/脚本默认值(见 §3.1, 别人的环境是别人的)
