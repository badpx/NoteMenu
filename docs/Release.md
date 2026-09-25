# 官网分发与 GitHub Release

本项目使用 Xcode 的 `NotesMate` Scheme 构建 `NotesMate.app`。`scripts/build-release.sh` 将 Release archive 导出为 **Developer ID Application** 签名的 App，制作带引导背景、左右图标和拖动箭头的 DMG，对 DMG 签名、公证并装订票据。打开 DMG 后将左侧 App 拖到右侧“应用程序”快捷方式即可安装。`scripts/publish-release.sh` 校验 DMG、版本和源码提交后，创建并推送对应的 Git tag，再创建 GitHub Release。脚本不会替你申请证书或创建公证凭据。

## 首次准备

1. 在 Apple Developer 账户创建 **Developer ID Application** 证书，并将证书及其私钥导入构建 Mac 的钥匙串。使用 `security find-identity -v -p codesigning` 查看可用身份。不要使用 Apple Development、Mac App Distribution 或临时自签名证书。
2. 为 `notarytool` 保存钥匙串凭据。若使用 Apple ID 认证，先在 [Apple 账户网站](https://account.apple.com/)的“登录和安全”→“App 专用密码”中生成一个密码（账户需开启双重认证），再运行以下命令；它会提示输入刚生成的 App 专用密码。不要把密码写入脚本或仓库。

   ```bash
   xcrun notarytool store-credentials NotesMate --apple-id 'you@example.com' --team-id TEAMID1234
   ```

   这里显式传入 `--apple-id` 和 `--team-id`，便于确认凭据属于预期团队；它们并非 `store-credentials` 命令本身的必需参数。如果运行不带这些参数的交互式命令时看到 `Path to App Store Connect API private key`，那是在询问另一种 API Key 认证方式的 `.p8` 私钥路径；使用本流程的 Apple ID 和 App 专用密码时，无需提供该文件，改用上面的显式参数命令即可。

   如果已有同一开发团队用于其他 App 公证的 App Store Connect **Team API Key**，可复用其 `.p8` 创建 NotesMate 专用的 Keychain profile，无需为每个 App 生成新密钥：

   ```bash
   xcrun notarytool store-credentials NotesMate \
     --key '/path/to/AuthKey_KEYID.p8' --key-id KEYID --issuer ISSUER_UUID
   ```

   用实际的 Key ID 和 Issuer ID 替换占位符。密钥须仍有效且允许 `notarytool` 使用；App Store Connect 的 Individual API Key 不支持 `notarytool`。`.p8` 私钥不要提交到仓库。

   如果同一团队的 API Key 已经保存为本机的 `notarytool` Keychain profile（例如 `fireflint-release`），也可直接在构建时设置 `NOTARY_PROFILE=fireflint-release`；profile 名称不与具体 App 绑定，无需重复运行 `store-credentials`。
3. 安装 Xcode 16 或更新版本，并通过 `xcode-select` 选中它；安装并登录 GitHub CLI（`gh auth login`）。本项目现有的 `.entitlements` 与 `Info.plist` 会由 Xcode 签入 App。

## 构建

先提交所有源码修改。正式发布时显式设置 `VERSION` 和递增的 `BUILD_NUMBER`；脚本把它们传给 Xcode 的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`，并在导出后核对 App 内的 `CFBundleShortVersionString` 与 `CFBundleVersion`。工程中的 `1.0` 和 `1` 只是日常本地构建的默认值，无需为每次发布手工改文件。

```bash
export VERSION=1.0
export BUILD_NUMBER=1
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID1234)'
export NOTARY_PROFILE=NotesMate
scripts/build-release.sh
```

构建脚本会从本机钥匙串中的 Developer ID Application 身份读取 Team ID，用于 Xcode archive、导出和签名校验；无需单独设置 `APPLE_TEAM_ID`。也可把 `DEVELOPER_ID_APPLICATION` 设置为该身份的 SHA-1 指纹。`notarytool` 的认证凭据独立于代码签名证书；脚本使用上一步创建的 `NotesMate` Keychain profile 提交公证。

假设 App 版本是 `1.0`，产物为：

```text
dist/v1.0/NotesMate-v1.0-macos.dmg
dist/v1.0/SHA256SUMS
dist/v1.0/SOURCE_COMMIT
dist/v1.0/BUILD_NUMBER
```

脚本会验证 App 的 Developer ID 签名、Team ID、Hardened Runtime 和安全时间戳，以及 DMG 的签名、完整性、公证结果、装订票据和 Gatekeeper 评估。DMG 布局由 `scripts/create-dmg.sh` 和 `scripts/create-dmg.applescript` 写入，背景源文件为 `assets/dmg-background.svg`；构建需要已登录的 macOS Finder 会话，并可能首次提示允许终端控制 Finder。公证可能需要较长时间；失败时会保留 `build/release-work.*` 的日志和提交结果供排查。`dist/` 和 `build/` 已被 Git 忽略。

## 发布

构建完成后运行发布脚本即可。它先校验 DMG 和 `BUILD_NUMBER`，再把 `v<版本号>` 注释标签创建在 `SOURCE_COMMIT` 指向的构建提交上，推送到 `origin`，最后创建 GitHub Release。已有同名本地或远端标签时，只有它指向同一构建提交才会继续；脚本不会移动已有标签，也不会发布与 DMG 版本或 Build Number 不一致的构建。如果标签已推送而 Release 创建失败，可修复原因后重新运行同一命令。

```bash
scripts/publish-release.sh v1.0
```

默认使用 GitHub 自动生成的发行说明。若要自行撰写，可设置 `RELEASE_NOTES_FILE=/absolute/path/release-notes.md`；若要先创建草稿，可在命令末尾加 `--draft`。Release 附件包含 DMG 和 `SHA256SUMS`。官网可链接到 `https://github.com/badpx/NotesMate/releases/download/v1.0/NotesMate-v1.0-macos.dmg`，将其中的版本号替换为实际版本。下载后打开 DMG，将 NotesMate 拖入“应用程序”。

正式公开前，建议在另一台未安装过 NotesMate 的 Mac 上下载最终 DMG，安装后验证首次启动、自动化权限弹窗和保存至系统备忘录的完整流程。

参考：[Apple 打包分发流程](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)、[Apple 公证要求](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)、[GitHub CLI Release](https://cli.github.com/manual/gh_release_create)。
