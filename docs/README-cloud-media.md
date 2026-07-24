# AdventureX Cloud Media 对接说明

契约文件：[`openapi-cloud-media.yaml`](./openapi-cloud-media.yaml)

## 本地联调

1. 启动 Cloud Media 服务（默认 `http://127.0.0.1:9000`）。
2. 真机调试时把基址换成电脑局域网 IP：

```powershell
cd mobile
flutter run -d 53740dd4 --dart-define=CLOUD_MEDIA_BASE=http://192.168.x.x:9000
```

3. 登录 / 注册后会自动签发并保存 UserToken。
4. Press 会上传 Draft 本地音频 → 轮询 READY → 写入 NFC（`contentId` + `nfc_url`）。
5. Collection 下拉刷新可重新 `listOwnedContents`。

## App 职责边界

- App 使用 **UserToken**；不持有 Trigger / Playback Token。
- Drafts 仍本地优先；Collection 合并云端 READY 条目。
- NFT Mint 不在本 OpenAPI 内，Press 末尾仍走本地模拟上链。
