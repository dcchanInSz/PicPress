# 签名、公证与隐私弹窗

PicPress 不联网、不读照片库、不碰相机麦克风，代码里没有任何会触发隐私授权的东西。
用户真正会遇到的弹窗，几乎全部来自 **macOS 对「这个 App 是谁、可不可信」的判断**，
而这件事只取决于一件事：**签名**。

这份文档说明每个弹窗从哪来、怎么消掉，以及仓库里对应的命令。

---

## 三种弹窗，三种解法

| 弹窗 | 什么时候出现 | 怎么消掉 |
| --- | --- | --- |
| 「无法验证开发者」/「已损坏，无法打开」 | 别人从网上下载的 App 没有签名，或签了但没公证 | Developer ID Application 证书 + 公证 → `make release` |
| 「PicPress 想访问你的『桌面』文件夹」 | App 主动遍历受保护目录；**或者每次构建都换了签名身份，macOS 把它当成新 App** | 稳定证书（`make cert` 或开发者证书）+ 只碰用户亲手交出来的文件 |
| 「想控制访达 / 其他 App」（自动化） | App 发送 Apple Events | 不使用 Apple Events；entitlements 留空 |
| 「是否允许接受传入的网络连接」（防火墙） | App 监听端口 | 静态链接 libwebp，零网络代码 |
| 「想要访问照片/麦克风/摄像头」 | 调用 Photos / AVCapture | 没有这些框架 |

一句话：**弹窗数量 ≈ 0，前提是签名稳定且已公证。**

---

## 签名身份是怎么选的

`make` 会调用 `scripts/sign.sh`，按下面的顺序挑第一个可用的身份
（`scripts/lib-signing.sh` 里实现）：

| 顺序 | 身份 | 能做什么 |
| --- | --- | --- |
| 1 | `$CODESIGN_IDENTITY` | 手动指定，优先于一切 |
| 2 | **Developer ID Application** | 可分发、可公证、任何 Mac 双击都不弹窗 |
| 3 | **Apple Development** | 本机有效、身份稳定（TCC 授权能记住），不能分发 |
| 4 | **PicPress Local Signing** | `make cert` 生成的自签名证书，同样身份稳定，仅本机 |
| 5 | ad-hoc（`-`） | 兜底。cdhash 每次构建都变，macOS 视作新 App，隐私弹窗会反复出现 |

无论用哪一种，签名都会带上：

- `--options runtime`（Hardened Runtime，公证的硬性要求）
- `Resources/PicPress.entitlements`（**空的**，见下）
- Apple 签发的证书还会带 `--timestamp`（安全时间戳，证书过期后签名依然有效）

```bash
make            # 构建 + 自动签名
make sign       # 只重新签名，并打印 Gatekeeper 结论
make doctor     # 体检：身份 / Runtime / entitlements / Gatekeeper / quarantine
```

---

## 本机开发：让授权只问一次

没有开发者证书时用 ad-hoc，每次 `make` 都会生成新的 cdhash。macOS 把每个构建
当成不同的 App，于是「PicPress 想访问你的…文件夹」会一次次重来。

解决办法是给这台 Mac 一张固定的证书：

```bash
make cert
```

它会在**登录钥匙串**里生成一张自签名证书 `PicPress Local Signing`（私钥不出本机，
只授权 `codesign` 使用），之后所有构建共用一个身份，系统问过一次就会记住。

> 这张证书只在本机受信。要发给别人，仍然需要 Developer ID + 公证。
> 删除它：`security delete-certificate -c "PicPress Local Signing" ~/Library/Keychains/login.keychain-db`

如果你已经装了 Xcode 并登录了开发者账号，通常会有 `Apple Development` 证书，
`make` 会直接用它，效果一样，而且不需要 `make cert`。

---

## 分发给别人：Developer ID + 公证

只有 **Developer ID Application** 证书签的 App 才能公证。它和 Apple Development
证书来自同一个开发者账号，只是用途不同：

1. Xcode → Settings… → Accounts → 选中团队 → **Manage Certificates…** → ＋ →
   **Developer ID Application**
   （或者 <https://developer.apple.com/account/resources/certificates>）
2. 把公证凭据存进钥匙串（一次性）：

   ```bash
   xcrun notarytool store-credentials picpress \
     --apple-id you@example.com \
     --team-id TEAMID \
     --password <App 专用密码>     # https://appleid.apple.com → 登录与安全 → App 专用密码
   ```

3. 出包：

   ```bash
   NOTARY_PROFILE=picpress make release
   ```

`make release` 做的事：

1. 用 Developer ID 重新签名 `PicPress.app`（Hardened Runtime + 时间戳）
2. 压缩上传，等 Apple 公证通过
3. 把公证票据**钉**到 App 上（`xcrun stapler staple`），离线安装也能过 Gatekeeper
4. 用钉过票据的 App 重新打包 `dist/PicPress.dmg`，签名后再次公证并钉票据
5. 用 `spctl` 复验，输出最终结论

也支持另外两种凭据方式：

```bash
# 环境变量
APPLE_ID=… APPLE_TEAM_ID=… APPLE_APP_PASSWORD=… make release

# App Store Connect API Key
APPLE_KEY_PATH=AuthKey_XXX.p8 APPLE_KEY_ID=XXX APPLE_ISSUER_ID=… make release
```

公证日志会留在 `.build/notary/`，被拒时脚本会自动 `notarytool log` 打出来。

---

## 为什么 entitlements 是空的

`Resources/PicPress.entitlements` 里一个键都没有，这是刻意的：

- 没有 `com.apple.security.network.client/server` —— 开不了网络
- 没有 `com.apple.security.automation.apple-events` —— 不会出现「想控制访达」
- 没有 `com.apple.security.device.camera/microphone`、`personal-information.*`
- 没有 `com.apple.security.cs.disable-library-validation` —— 库验证保持开启
- libwebp 是**静态库**，运行时不需要加载任何第三方 dylib，所以也不需要 JIT 相关豁免

也就是说：**签名只证明「这是谁做的」，不额外授予任何能力。**

---

## 隐私设计（代码层面）

| 做法 | 位置 | 效果 |
| --- | --- | --- |
| 只处理用户显式交出的文件 | 拖放 `DropRootView`、`NSOpenPanel`、`application(_:open:)` | 系统视为用户授权，不弹 Files & Folders 弹窗 |
| 不遍历任何固定目录 | `CompressionQueue.expand` 只展开被拖入/选中的文件夹 | 不会偷偷扫 `~/Pictures` |
| 不联网 | 没有任何 `URLSession` / socket / 上报代码 | 不会触发本地网络、防火墙弹窗 |
| 临时文件放系统临时目录 | `TMPDIR/PicPress-<pid>/`，退出时删除 | 不写用户目录，不残留 |
| 空 entitlements + Hardened Runtime | `Resources/PicPress.entitlements` | 没有额外特权 |
| 用途说明写清楚 | `Resources/Info.plist` 的 `NS*UsageDescription` | 万一弹窗，用户看到的是「只读取你拖入的图片」而不是空白理由 |

---

## 排查

```bash
make doctor          # 一次性看清签名、Runtime、entitlements、Gatekeeper
```

常见情况：

**双击提示「无法验证开发者」**
下载来的 App 没有被公证。要么让作者出公证版，要么本机执行：

```bash
xattr -dr com.apple.quarantine /Applications/PicPress.app
```

**「PicPress 已损坏，无法打开」**
通常是签名被破坏（比如手动改过 `Info.plist`、或者用 `zip` 而不是 `ditto`
打包丢了资源分叉）。重新 `make` 即可，别用 `xattr` 硬解。

**授权弹窗反复出现**
说明每次运行的构建签名身份都在变。跑 `make doctor` 看身份，跑 `make cert`
（或安装开发者证书）固定下来；然后清掉旧记录重新授权一次：

```bash
tccutil reset SystemPolicyDesktopFolder   com.dcchanin.picpress
tccutil reset SystemPolicyDocumentsFolder com.dcchanin.picpress
tccutil reset SystemPolicyDownloadsFolder com.dcchanin.picpress
```

**换证书之后又弹窗**
签名身份变了 = 新 App，这是 TCC 的正常行为。用 `tccutil reset` 清掉后再授权。

**证书过期**
`make doctor` 会显示 `Authority`。Developer ID 证书有效期一年，但带安全时间戳的
旧签名在证书过期后依然有效；新构建则需要续期证书。
