# Kazumi For TV 发版规范

面向「把 APK 传到 GitHub Releases」这一件事的检查清单。每次发版照着走一遍，不要凭记忆。

## 一、版本号

| 位置 | 写法 | 说明 |
| --- | --- | --- |
| `pubspec.yaml` | `version: 1.0.2-beta+20405` | `1.0.2-beta` 是 versionName，`20405` 是 versionCode |
| 界面显示 | `1.0.2 beta` | 关于页用 `replaceFirst('-', ' ')`，不要改 pubspec 去迁就显示 |
| GitHub tag | `1.0.2-beta` | **必须与 versionName 完全一致**，应用内检查更新拿 tag 比版本，不一致就误报有新版本 |

- versionCode 每次发版 **+1**，且必须 **大于上游 Kazumi**（上游 2.4.3 是 20403，本仓库从 20404 起），
  这样从上游版覆盖安装不用先卸载。
- 预发布用 `-beta` 后缀；等真正稳定了再发 `1.1.0+20410` 这种不带后缀的。

## 二、发版前自检

```bash
flutter analyze --no-fatal-infos            # 必须 0 error
flutter test                                # version_test 等单测全绿
```

真机（投影 / 电视盒子）过一遍最小验收清单：

- 冷启动进 TV 主界面，**不弹更新框**
- 推荐 / 时间表 / 追番 / 我的 四个 tab 都能进，焦点框始终可见
- 搜索：主页放大镜 → 搜索页 → OK 弹窗 → 打字 → 搜索有结果
- 规则管理：进页白框在「添加规则」，上/下/右都能走，搜索是胶囊
- 详情页 → 选源 → 播放，OSD 里剧集 / 弹幕 / 倍速都能按到
- 设置 → 关于页版本号显示正确

## 三、构建

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
flutter build apk --release          # 绝对不要加 --no-pub（会复用调试期插件注册表，编译失败或白屏）
```

看到 `✓ Built build/app/outputs/flutter-apk/app-release.apk (78.x MB)` 才算成功；
构建中途不要改源码，否则前端会读到不一致的源码。

## 四、签名（每次发版必做，否则装上去是 debug 证书）

```bash
BT="$HOME/Library/Android/sdk/build-tools/$(ls $HOME/Library/Android/sdk/build-tools | tail -1)"
PW=$(grep storePassword android/key.properties | cut -d= -f2)

"$BT/zipalign" -f -p 4 build/app/outputs/flutter-apk/app-release.apk /tmp/rel-aligned.apk
"$BT/apksigner" sign --ks android/keys/kazumi-tv-release.jks --ks-key-alias kazumi-tv \
  --ks-pass "pass:$PW" --key-pass "pass:$PW" \
  --out KazumiForTV-<versionName>-arm64-universal.apk /tmp/rel-aligned.apk

"$BT/apksigner" verify --print-certs KazumiForTV-<versionName>-arm64-universal.apk | head -2
```

- 证书 DN 必须是 `CN=Kazumi TV, OU=Release, O=Kazumi TV Fork, ...`，不是 `CN=Android Debug`。
- 私钥 `android/keys/kazumi-tv-release.jks` + `android/key.properties` 不入库，仓库外另存
  `~/Documents/kazumi-tv-keys/`。**这把钥匙丢了就再也发不了增量更新**，换签名老用户必须卸载重装。
- 证书 SHA-256 固定为 `63E6979564B0B57CF0E99432044EFB0C3F0036101E9F8FACF7772B0D8878A057`，
  发版说明里贴一遍，方便用户核对。

## 五、产物命名与核对

```
KazumiForTV-1.0.2-beta-arm64-universal.apk
```

- 应用显示名：`Kazumi For TV`（`AndroidManifest.xml` 的 `android:label`）
- 文件名格式：`KazumiForTV-<versionName>-arm64-universal.apk`；将来出 arm32/全 ABI 包再加后缀
- 核对：

```bash
"$BT/aapt2" dump badging KazumiForTV-1.0.2-beta-arm64-universal.apk | grep -E '^package|application-label'
# 期望：versionCode='20405' versionName='1.0.2-beta' / application-label:'Kazumi For TV'
shasum -a 256 KazumiForTV-1.0.2-beta-arm64-universal.apk
```

## 六、GitHub Release 怎么填

1. 先 commit & push 代码，`git tag 1.0.2-beta && git push origin 1.0.2-beta`（tag 与 versionName 一致）。
2. Release 标题：`Kazumi For TV 1.0.2 beta`。
3. 正文直接贴本仓库 `RELEASE_NOTES.md` 的内容（改本版更新日志 + 换 sha256）。
4. 附件只传签名后的 `KazumiForTV-*.apk`；不要传 `build/app/.../app-release.apk`（那是没签名的中间产物）。
5. 勾选 **Set as the latest release**；预发布可以勾 Pre-release，但勾了以后应用内检查更新仍会拿到它，
   版本号必须大于已发布版本。

## 七、合规

- 上游是 **GPL-3.0**：源码必须公开（本仓库即源码），`LICENSE` 原样保留，Release 里写明「基于 Predidit/Kazumi」。
- 不要把原作者 Logo、下载站链接、上游 API 镜像当作自己的下载渠道；应用内检查更新指向本仓库。
- 规则由社区提供，说明里写清「仅采集与播放，版权归权利人所有」。

## 八、发版后自检

- 用旧版本覆盖升级一次（`adb install -r -g`），确认数据没丢、版本号变了。
- 冷启动看有没有「发现新版本」误报（有就是 tag 与 versionName 不一致，或者 `latestApp` 又指回上游）。
- 把这一版的 sha256 记到 Release 正文和本文件的下方台账里。

## 发版台账

| 版本 | versionCode | tag | 证书 SHA-256 | APK SHA-256 |
| --- | --- | --- | --- | --- |
| 1.0.1 beta | 20404 | `1.0.1-beta` | `63E69795…78A057` | — |
| 1.0.2 beta | 20405 | `1.0.2-beta` | `63E69795…78A057` | `557f8f671cebe699e62a1fbcf9815ccdd298ac0a4a5b4dff8b4dd7d294066d52` |
