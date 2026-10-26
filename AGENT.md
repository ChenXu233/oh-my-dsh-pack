# AGENT.md

给在本仓库里干活的 AI agent 和人类看的约定。先读这一节, 再改任何东西。

## 0. 主仓库是 CNB, GitHub 只是它的同步镜像

**规矩: 提交后只推 CNB, 不要直接推 GitHub。**

| 远端 | 角色 | 谁能推 |
|---|---|---|
| `cnb` (`cnb.cool/ChenXu233/oh-my-dsh-pack`) | **主仓库 / 唯一真源** | 人和 agent, 提交即推这里 |
| `origin` (`github.com/ChenXu233/oh-my-dsh-pack`) | **CNB 流水线的同步镜像**, 只读 | 只有 CNB 流水线的 mirror 阶段 |

理由:

- 镜像是在 CNB 上构建的 (`.cnb.yml` 的 build + push 到 `docker.cnb.cool`), 服务器拉的是
  这个制品库里的镜像。CNB 才是"构建结果正确"的那一边, 它的仓库状态才是权威。
- GitHub 那边由 `.cnb.yml` 的 "mirror to github" 阶段用 `git push --mirror` 自动同步,
  是单向的产物, 不是第二个编辑点。往 GitHub 直推会造成两边历史分叉, 反而让 CI 同步失败。

所以 agent 的动作序列是: 改文件 -> 本地 commit -> `git push cnb <branch>` -> 等 CNB 流水线
(build image -> push 制品库 -> mirror 到 GitHub -> 可选 SSH 部署)。**不要执行 `git push origin`。**

另外: 远端 URL 里不要内嵌 token。用 credential helper 或 `.netrc`, 别把凭证写进
`.git/config` 的 URL 里。

服务器上的部署副本 (`~/harness-deploy`) 建议**直接克隆 CNB**。若它克隆的是 GitHub, 就多了一跳
镜像延迟: 流水线里 mirror 阶段先于 deploy 阶段, 所以时序上仍能拿到最新提交, 但"以 CNB 为真源"
这条规矩在服务器上最好也成立。

## 1. 这套"免发布迭代"链路只服务于插件作者本人

仓库里有两条装插件的路子, 适用范围不同:

| 链路 | 文件 | 适用对象 | 改代码要做什么 |
|---|---|---|---|
| 发布链路 | `bootstrap/10-plugins.sh` 的 `PLUGINS` 列表 | 所有人 | 发一个 npm 版本 + 重建镜像 |
| 开发链路 | `bootstrap-dev/20-link-plugins.sh` + `docker-compose.dev.yml` | **只有 dsh-workspace-mesh 的作者本人** | 同步构建产物 + 重启容器 |

开发链路的前提是"你手上有这份插件的源码"。仓库的使用者没有这份源码, 他们应该:

- 要插件 -> 直接改 `bootstrap/10-plugins.sh` 的 `PLUGINS` 列表, 填自己要的 npm 包名;
  或者干脆不碰这个文件, 启动后在网页的插件管理器里装。
- 不要照抄 `docker-compose.dev.yml` 的挂载。挂一个空目录进去, 只会在日志里留下一句
  `[dev] skip`, 对你没有任何好处。
- 不要把 `bootstrap-dev/` 当成"必须的组件"。它是可选的开发便利, 删掉不影响标准部署。

一句话: `bootstrap-dev/`、`docker-compose.dev.yml`、`scripts/sync-mesh.ps1` 是作者本人的
开发脚手架; 别人请遵循他们自己的插件清单。

## 2. 不暴露个人信息与凭据

- **不写具体主机地址**。远端主机用 SSH config 别名 (见 `~/.ssh/config`), 仓库里只出现别名,
  例如 `dsh-server`。这个别名指的是"跑 dsh 的那台机器", 与具体插件无关, 将来换插件、换开发链路都还用它。
  同步脚本的 `-SshHost` 默认取环境变量 `DSH_SSH_HOST` 或别名 `dsh-server`。
- **不写凭据**。API key、token、私有仓库地址一律不进仓库; 放环境变量, 或放 `.env`
  (已在 `.gitignore` 里)。
- **不写私有仓库地址**。`dsh-workspace-mesh` 尚未发布到 npm, 仓库里也不出现它的私有源地址。
- 宿主机路径用环境变量传 (`DSH_MESH_SRC`), 默认值用服务器侧的通用路径, 不含任何主机标识。

## 3. 改动的影响面

| 改了什么 | 需要重建镜像? | 需要 git pull + up -d? |
|---|---|---|
| `bootstrap/*.sh` | **是** (bootstrap 目录是 COPY 进镜像的) | 否, 但要 pull 新镜像 |
| `bootstrap-dev/*.sh` | 否 | 是 (`git pull` 后 `up -d` 即可) |
| `docker-compose.yml` | 否 | 是 |
| `docker-compose.dev.yml` | 否 | 是 |
| `Dockerfile` | **是** | 否 |

判定口诀: 在 `/opt/bootstrap` 里的东西跟镜像走, 在 `/opt/dev` 里的东西跟仓库走。

## 4. 机制备忘 (改之前先懂)

- `dsh plugin --profile web add <spec>` 会在 profile 目录里跑 pnpm。spec 可以是 npm 包名、
  git 地址、tarball, 也可以是 `link:/abs/path` 或 `file:/abs/path`。
- pnpm 跑完后 DSH 会 reconcile: 新装的包若声明了 `dsh.bundle`(自带 `cordis.patch.yml`),
  会被写进 profile 的 `dsh.profile.bundles`, 并按它的 patch 组合出对应的行, 插件随之挂载。
  所以 `link:` 安装是能生效的, 不需要手工改 profile。
- 插件代码改动要重启 dsh 进程才生效; 改配置(行级 override)在 profile 开了 HMR 时可以热生效。
- `assignmentFile` 这类相对路径是相对**宿主进程 cwd** 解析的, 容器里 cwd 是 `/data/workspace`,
  也就是 dsh-workspace 卷。
- `dsh plugin` 依赖 PATH 上的 pnpm。镜像里如果没有, 报的是 `pnpm was not found`。

## 5. 提交前自查

- [ ] 仓库里没有出现 IP、域名、用户名、密钥、私有仓库地址
- [ ] 没有改动标准部署的行为(别人 clone 下来应当开箱即用)
- [ ] 新的可选能力都在明确的 opt-in 开关后面(环境变量或单独的 compose 覆盖层)
- [ ] 没有把 `bootstrap-dev/` 里的东西挪进 `bootstrap/`(那会让别人被迫重建镜像)
