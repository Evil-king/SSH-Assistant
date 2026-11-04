# SSH Assistant

macOS 原生小工具：把 SSH 主机信息（别名 / IP / 端口 / 用户 / 密码）集中存到一份 `hosts.json`，
一键写进 `~/.ssh/config`、iTerm2，并在连接时自动填密码。列表里双击就能连。

> 纯本地工具：不联网、不上传任何数据；密码只存在本机 600 权限文件里。

## 功能

- **主机列表**：搜索（名称 / 别名 / IP / 用户）、双击打开、`⌘E` 编辑、`⌘N` 新增
- **表单即改即写**：保存后自动更新 SSH 别名、iTerm2 Dynamic Profile、密码表、`.command` 快捷方式
- **多终端**：系统终端 Terminal / iTerm2 / WezTerm / kitty / Alacritty / Ghostty（自动检测已安装的）
  - iTerm2 已有窗口时**开新标签**（没有窗口才开新窗口）
- **自动密码**：`wssh` 用 `SSH_ASKPASS` 把密码交给 ssh，不出现在命令行与 `ps` 里
- **可选免密**：`setup-ssh-keys.sh` 批量 `ssh-copy-id`
- 原生 AppKit 界面，自带图标（终端窗口 + `>_`，添加版带加号）

## 两个入口

| App | 行为 |
|---|---|
| `SSH 主机.app` | 打开主机列表 |
| `添加SSH.app` | 打开主机列表，并自动弹出「新增」表单 |

两个 App 共用同一份二进制，靠 bundle id 区分（见 `build_app.sh`）。

## 目录

| 文件 | 作用 |
|---|---|
| `hosts.json` | 主机数据源（**不入库**，从 `hosts.example.json` 复制） |
| `SSHHosts.swift` | 唯一 App 源码：列表 + 表单 + 终端适配 |
| `add_host.py` | 命令行新增/编辑：写 JSON → 生成 → 安装 |
| `gen_all.py` | 由 `hosts.json` 生成 ssh 配置 / iTerm2 profile / 密码表 |
| `install.sh` | 安装到 `~/.ssh`、`~/.local/bin`、`~/Applications` |
| `build_app.sh` | 编译打包两个 App（需要 Xcode Command Line Tools） |
| `wssh` | 会话包装：查密码表 → `SSH_ASKPASS` → `ssh` |
| `work-info-askpass` | askpass 助手（按 `用户@主机:端口` 查密码） |
| `ssh-hosts` / `add-ssh-host` | 从命令行打开两个 App |
| `setup-ssh-keys.sh` | 批量装公钥，升级为免密登录 |
| `make_icons.swift` / `make_icns.sh` | 代码绘制图标并生成 `.icns` |
| `dist/` | 预编译的两个 App（可直接用，见下） |

## 快速开始

```bash
git clone git@github.com:Evil-king/SSH-Assistant.git
cd SSH-Assistant
cp hosts.example.json hosts.json      # 改成你自己的主机
./install.sh                          # 写入 ~/.ssh、iTerm2、~/Applications
```

也可以直接用 `dist/` 里的 App：把它们放到仓库根目录（和 `hosts.json` 同级），或设置环境变量
`WORK_SSH_TOOL_DIR=/path/to/SSH-Assistant`。App 需要仓库里的 `add_host.py` 来保存数据。

从源码构建：

```bash
./build_app.sh     # 需要 swiftc（xcode-select --install）
./install.sh
```

## hosts.json 字段

```json
{
  "alias": "demo-web",          // SSH 别名：ssh demo-web
  "name": "演示 Web 服务器",     // 列表显示名
  "host": "192.0.2.10",
  "port": 22,
  "user": "root",
  "password": "change-me",
  "tags": ["生产", "demo"],     // 第一个标签决定环境色
  "color": "#1f6feb"            // 生产蓝 / 预生产黄 / 测试紫 / 其他灰
}
```

命令行也能改：

```bash
printf '密码\n' | ./add_host.py --alias demo --host 192.0.2.10 --port 22 \
  --user root --password-stdin --env prod --tags demo --json
```

## 工作原理

```
App ──保存──> add_host.py ──> hosts.json
                   ├─ gen_all.py  → ssh_config_work / dynamic-profiles.json / credentials.tsv
                   └─ install.sh  → ~/.ssh/config.work + iTerm2 DynamicProfiles + ~/.local/bin/wssh
打开会话：wssh <别名> → 查 ~/.ssh/work-info-credentials → SSH_ASKPASS_REQUIRE=force → ssh
```

## 安全

- `hosts.json`、`~/.ssh/work-info-credentials` 都是**明文密码**（600 权限），和把密码写进 `~/.ssh/config` 同级风险；
  `.gitignore` 已排除，别提交，也别放同步盘。
- 更安全的做法：`./setup-ssh-keys.sh -y` 装公钥后删掉密码表，只留密钥登录。
- 密码不进 `argv`、不进 `ps`（走 stdin + askpass）。

## 已知限制

- 仅 macOS 11+（用了 AppKit / Swift concurrency 之外的现代 API）
- Terminal.app 的标签**无法由脚本创建**（`make new tab` 报 -10000），只能开新窗口；iTerm2 支持新标签
- 首次用 iTerm2 打开会请求「自动化」权限（系统设置 → 隐私与安全性 → 自动化）
- 需要 macOS 自带 `/usr/bin/python3` 运行 `add_host.py`
