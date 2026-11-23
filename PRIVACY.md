# Tethera Privacy Policy / 隐私政策

Effective date / 生效日期：2026-11-22

[English](#english) · [简体中文](#简体中文)

## English

Tethera is an iPhone and iPad client for [Herdr](https://herdr.dev). It shows the coding-agent sessions (such as Claude Code and Codex) that Herdr runs on your own computer, and lets you reply to them. Tethera is developed by Tianang Han ("we").

**Short version:** we have no accounts, no analytics, no ads and no tracking. Your sessions travel between your phone and your own computer. The only data our servers keep is what is needed to send you push notifications.

### What stays on your devices

- **Session content.** Conversations, terminal output, file changes and usage figures are read from your own computer and shown on your phone. We do not receive or store them.
- **Keys.** SSH keys and pairing keys are kept in your device's Keychain (this device only, not synced to iCloud).
- **Camera, microphone, speech and photos.** The camera scans pairing QR codes and takes photos you choose to send to your agent. Speech-to-text runs on your device. Saving an image to Photos happens only when you ask. None of this is sent to us.
- **iCloud sync** (on by default, can be turned off in Settings). Your list of computers, connection settings, host fingerprints and public connector details sync between devices signed in to your own iCloud account, using Apple's iCloud key-value storage. No keys are synced. We cannot read your iCloud data.

### What passes through servers

- **Relay.** When you connect through the relay, traffic between your phone and your computer is end-to-end encrypted. The relay (by default `tethera-iroh.borry.org`, operated by us; you can switch to the public n0 relays or turn the relay off) only forwards encrypted data and cannot read it. Like most internet services, it necessarily sees the IP addresses of the two ends while forwarding.
- **Push notifications.** If you turn on notifications, the app registers with our push service (`tethera-push.borry.org`). The service stores:
  - a SHA-256 hash of a random key generated on your phone,
  - your Apple Push Notification service (APNs) device token, and Live Activity push tokens if you use Live Activities,
  - when the registration was created and when a notification was last sent.

  When your computer has something for you (an agent finished, or is waiting for your confirmation), your computer sends the notification text (such as the session title and the agent's latest message) to the push service, which forwards it to Apple for delivery. The text is not stored and not logged. Tokens are deleted when you turn notifications off, or when Apple reports that a token is no longer valid.
- **Update checks.** The app may make one request to GitHub (`github.com/Ami0307/tethera-releases`) to check for the latest connector version. GitHub's own privacy policy applies to that request.

### What we do not do

We do not collect analytics, crash reports, contacts, location, advertising identifiers or any account information. We do not sell or share data, and we do not track you across apps or websites.

### Children

Tethera is a developer tool and is not directed at children.

### Changes and contact

If this policy changes, the new version will be published at this address with a new effective date. Questions: open an issue at <https://github.com/Ami0307/tethera-releases/issues>.

## 简体中文

Tethera 是 [Herdr](https://herdr.dev) 的 iPhone / iPad 客户端，用来查看并回复 Herdr 在你自己电脑上运行的编程 agent 会话（例如 Claude Code、Codex）。Tethera 由 Tianang Han（下称「我们」）开发。

**简要说明：** 没有账号、没有统计分析、没有广告、不追踪。你的会话只在手机和你自己的电脑之间传输。我们的服务器只保存发送推送通知所必需的数据。

### 留在你设备上的数据

- **会话内容。** 对话、终端输出、文件改动和用量数据都从你自己的电脑读取，在手机上显示。我们不接收、不保存。
- **密钥。** SSH 密钥和配对密钥存在设备的钥匙串里（仅本机，不同步 iCloud）。
- **相机、麦克风、语音和照片。** 相机用于扫描配对二维码，以及拍摄你选择发给 agent 的照片。语音转文字在设备上完成。只有你要求时才把图片存入相册。这些都不会发给我们。
- **iCloud 同步**（默认开启，可在设置中关闭）。电脑列表、连接设置、电脑指纹和连接器的公开信息，通过 Apple 的 iCloud 键值存储，在登录同一 iCloud 账号的设备之间同步，不同步任何密钥。我们无法读取你的 iCloud 数据。

### 经过服务器的数据

- **中转。** 通过中转连接时，手机和电脑之间的内容端到端加密。中转服务器（默认为我们运营的 `tethera-iroh.borry.org`，可以改用 n0 公共节点或关闭中转）只转发密文，无法读取内容。和大多数网络服务一样，转发时它必然能看到两端的 IP 地址。
- **推送通知。** 打开通知后，App 会在我们的推送服务（`tethera-push.borry.org`）登记。服务保存：
  - 手机上随机生成的 key 的 SHA-256 哈希；
  - 你的 Apple 推送通知服务（APNs）设备 token，以及使用实时活动时的实时活动推送 token；
  - 登记时间和最近一次推送的时间。

  当电脑上有事需要你（agent 完成了，或在等你确认），电脑会把通知文字（如会话标题、agent 最后一条消息）发给推送服务，由它转交 Apple 送达。这些文字不保存、不写日志。关闭通知，或 Apple 告知 token 已失效时，token 会被删除。
- **检查更新。** App 可能向 GitHub（`github.com/Ami0307/tethera-releases`）发一次请求，查询连接器的最新版本。该请求适用 GitHub 的隐私政策。

### 我们不做的事

不收集统计分析、崩溃报告、通讯录、位置、广告标识符或任何账号信息。不出售、不共享数据，不跨 App 或网站追踪你。

### 儿童

Tethera 是开发者工具，不面向儿童。

### 变更与联系

本政策如有变更，新版本会发布在同一地址并更新生效日期。如有问题，请在 <https://github.com/Ami0307/tethera-releases/issues> 提 issue。
