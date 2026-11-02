# 影之刃零 PvP 网络启动器
2026-11-03 已通过单真实游戏模拟对手与双真实游戏互攻验收。`Start-PvP-Prototype.cmd` 启动单实例来袭演示；`Start-Real-PvP-Test.cmd` 完成双实例自动互攻。两者先备份个人存档、切换测试存档，结束后恢复个人进度；默认有运行时限。见 [实际开发进度](DEVELOPMENT-STATUS.md) 和 [验收摘要](verification/pvp-20261103.json)。当前已停止测试并恢复个人存档。

Windows x64 开发版，自带 .NET 9 运行库，无 Python 依赖。双击 `Start-PB0.cmd`，选创建房间或输入完整邀请码。本机开发测试用 `Start-Development.cmd`，它选择独立游戏副本；原安装目录保持用于正常游戏。邀请码包含房间密钥，24 小时有效，只发给另一位玩家。

```powershell
.\dist\PB0\PB0.exe host
.\dist\PB0\PB0.exe join PB0.完整邀请码
```

会话中输入 `msg 你好` 发消息，`status` 查看状态，`game` 配置并直接启动原版游戏，`quit` 退出并清理本次 EasyTier 子进程。连接状态只有在收到经过签名验证的双向心跳后才显示 connected。显示的是应用层往返延迟；p2p/relay 来自 EasyTier 路由信息。

## 当前交付

- 自动启动官方 EasyTier 2.6.4，随机房间名/密钥、完整邀请码、两人虚拟 IP、UDP 双向消息与确认重传、重复消息过滤、心跳/RTT、断线检测和核心退出后的重启。
- 使用 EasyTier 自带 UDP 端口转发及用户态网络栈。`--no-tun`，不加载驱动、不创建网卡、不设置物理网卡 IP/DNS/系统路由。显式关闭 DNS 接管和 UPnP；不自动修改防火墙。每个进程使用独立监听/RPC/转发端口。
- 正常退出及启动器异常退出时，由 Windows Job 清理本程序启动的核心。不会按进程名结束其他 EasyTier 实例。
- 可通过已安装 Phantom Pact 的 INI 接口打开 PvP，设置相同签名密钥，并将其 UDP 流量接入 EasyTier。退出时恢复本次修改的 INI；不覆盖运行中其他会话的配置。
- Cloudflare 备用通道尚未实现；本版本不会把中继连接当作失败，也不会产生 Cloudflare 费用。

## 快速测试

```powershell
node scripts/test-network.mjs --local --reconnect
node scripts/test-network.mjs --public
node scripts/test-network.mjs --relay
```

测试启动两个独立客户端，检查邀请码、两向消息及确认、RTT、虚拟 IP 路径和退出清理；`--reconnect` 另外结束本测试自己创建的核心，检查自动恢复。`--local` 仅通过本机 EasyTier 监听端点连接。`--public` 通过邀请码中的共享节点发现，不包含直连提示；即使成功，也不能替代异地两台电脑的公网实测。

`--relay` 另外启动一个仅监听 localhost 的临时共享节点，双方关闭 P2P，要求真实路由显示 relay 并完成消息往返。它用于验证 EasyTier 中继路径，不代表公网节点可用。

默认共享节点来自维护者公开分享（slarker 美国节点和 EasyTier 社区日本节点）。2026-11-02 已验证经公网共享节点中继的双向消息与 RTT。两份客户端都在本机，此测试不能代替异地两台电脑实测。旧文档中的 `public.easytier.cn` 和其 `.top` 别名在本次 DNS 核对中返回 NXDOMAIN，未放入默认列表。共享节点没有可用性保证。开发时可由房主覆盖，节点列表随邀请码传给客人：

```powershell
.\dist\PB0\PB0.exe host --peers tcp://节点地址:端口,udp://节点地址:端口
```

## 游戏接入

默认游戏目录 `D:\SteamLibrary\steamapps\common\PBZ`，可用 `--game-root` 指定。`PB0 doctor` 检查所需文件。

1. 关闭游戏，运行 `scripts/backup-game-saves.ps1`。在 `backups` 中生成存档副本及逐文件 SHA-256 清单，`runs/latest-save-backup.txt` 记录位置。备份不会删除或覆盖源存档。
2. 本机准备的 UE4SS 包在 `tools/pbz-ue4ss`，Phantom Pact 原始发布包在 `tools/phantom-pact-release`。`scripts/install-game-mod.ps1` 在确认存档副本完整后安装；遇到现有 Mod 目录就停止，避免覆盖。
3. 双方创建/加入同一房间，连通后输入 `game`。房主原生 Mod 监听本机 UDP，客人的 localhost 端口由 EasyTier 转发至房主虚拟 IP。`Connect = Tailscale` 是该 Mod 的 IP 传输设置名称，不需要 Tailscale 软件或账户。

游戏使用正版原始 `platform/steam/PBZ.exe` 直接启动，提供 960×540 窗口参数；不会改可执行文件或绕过 DRM。若游戏自身要求正常授权，应按游戏要求处理。

host 和 guest 副本已分别通过真实游戏保存接口写盘验证，Saved/SaveGames 与 user-data 均独立。双实例仅接受不同且已有隔离证据的测试副本，并须显式 `--allow-isolated-games`；不会自动允许原安装参与。`PBZCOOP_INSTANCE` 单独不构成存档隔离证明。

`scripts/probe-real-game.ps1` 只做单实例直接启动和日志检查，不自动读档/创建人物。原存档备份始终留在 `backups`，不自动还原覆盖新的游戏进度。

开发测试改用 `scripts/prepare-test-profile.ps1` 生成的 `game-instances/host`。程序文件原样复制，只有资源/运行库目录是指向原安装的目录联接，Saved 和 Mod 配置为独立目录。不能递归删除联接的目标目录。

`scripts/test-game-bridge.ps1` 保护原安装活动存档并校验个人备份；默认验收完整 PvP，要求真实可见运动实体、实际技能和 HP/架势变化、引擎 Perfect 弹反与原生 V 回传。`-Dual` 测试两个真实游戏进程，已验证双方各 64 点真实伤害、弹反的攻击方 60 点架势惩罚及普通格挡。

原型是开发测试版：单进程模拟端用于来袭/防御，不判定模拟端自身受伤/胜负；双向真实伤害由双进程入口验证。锁屏运行已通过游戏数据验证，尚未目视核对渲染截图，亦未测试异地两台电脑的实战。

测试目录中的 `steam_appid.txt` 是 [Steam 官方支持的直接启动开发配置](https://partner.steamgames.com/doc/api/steam_api#SteamAPI_RestartAppIfNecessary)，只防止游戏被重新启动到原安装目录。游戏的正版授权仍由原程序和 Steam API 处理。

## 构建及依赖

```powershell
.\scripts\setup.ps1
```

需要 Node.js（仅下载/测试）与 .NET 9 SDK（仅构建）。默认生成自带运行库的 Windows x64 目录，玩家无需安装 .NET。也可用 `scripts/build.ps1 -FrameworkDependent` 生成较小的依赖本机 .NET 版本。源码不依赖第三方 NuGet 包；微软运行库包缓存于项目内，`NuGet.Config` 关闭外部包源。产物在 `dist/PB0`，包含微软运行库和无需驱动的 EasyTier 核心/CLI，不带原游戏文件。

## 来源与许可

- [EasyTier 2.6.4](https://github.com/EasyTier/EasyTier/releases/tag/v2.6.4)，独立未修改程序，LGPL-3.0，许可在 `licenses/EasyTier-LGPL-3.0.txt`；源码由同一发布页和仓库提供，可替换成兼容核心。
- [EasyTier 共享节点用法](https://doc.easytier.cn/guide/network/fast-networking.html)；[社区共享节点声明](https://github.com/orgs/EasyTier/discussions/2429)。
- [slarker 节点维护者的使用说明](https://wiki.slarker.me/application/easytier.html)。当前 IPv4 经独立 DNS 查询核对；域名仅用于发现公开节点，不修改系统 DNS 配置。
- [PBZ 专用 UE4SS 包](https://github.com/KintaroModding/ue4ss/releases/tag/v3.0.1-1195-g1ceefac8)，MIT；本机下载 ZIP 已核对 GitHub 发布 SHA-256。
- [Phantom Pact 1.4.1 原始发布包](https://github.com/yhsharaf/PhantomPact/releases/tag/v1.4.1)。仓库未附明确源码许可证；本项目不打包或上传上游 Lua/C++ 文件；自有适配器复用其接口。安装脚本在备份后仅给隔离副本加加载入口和旧启发式的兼容条件，原安装不改。`reference` 仅是本机研究用检出，不进入发行目录。若要再分发其源码/修改版，需先明确授权。

网络事件日志在每次运行的 `runs` 目录；邀请码单独保存，不写入常规事件日志。此版本尚未完成异地公网与真实双人战斗验证，不应视为完整 PvP 成品。
