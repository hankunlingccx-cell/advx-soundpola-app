# AdventureX Cloud Media 对接说明

契约文件：[`openapi-cloud-media.yaml`](./openapi-cloud-media.yaml)

预设基址：`https://soundpola.babelbeast.com`（可在登录页「服务器设置」改写；旧部署可能带 `:9000`）

## 运行

```powershell
cd mobile
flutter run -d 53740dd4
```

## 联调流程

1. 登录 / 注册后会自动签发并保存 UserToken。
2. Press／预上传：先传音频拿 `content_id`，再传本机 bake 的 `visual.mp4` → 常直接 `READY` → 写入 NFC（`contentId` + `nfc_url`）。
3. Collection 下拉刷新可重新 `listOwnedContents`。
4. 公开预览：`/preview/{content_id}/video`、`/preview/{content_id}/audio`。

# 上传协议（App 已对齐：两段式）

## 1) 上传音频

```http
POST /api/v1/contents
Authorization: Bearer <USER_TOKEN>
Content-Type: multipart/form-data; boundary=...
```

- 文件字段名必须是 **`audio`**
- 不要手写死 `Content-Type: multipart/form-data`（须带 boundary，由客户端自动生成）
- 成功：`201` + `content_id` / `state`（多为 `UPLOADED`）/ `status_url`

```bash
CONTENT_ID=$(curl -s -X POST https://soundpola.babelbeast.com/api/v1/contents \
  -H "Authorization: Bearer $USER_TOKEN" \
  -F "audio=@/path/to/audio.mp3" \
  | python -c "import sys,json;print(json.load(sys.stdin)['content_id'])")
```

## 2) 上传可视化 MP4

本机 Indexed-MJPEG bake 后，Android 编码 `sounds/{id}/visual.mp4`，再：

```http
POST /api/v1/contents/{content_id}/video
Authorization: Bearer <USER_TOKEN>
multipart field: video=@visualization.mp4
```

```bash
curl -X POST "https://soundpola.babelbeast.com/api/v1/contents/$CONTENT_ID/video" \
  -H "Authorization: Bearer $USER_TOKEN" \
  -F "video=@/path/to/visualization.mp4"
```

成功示例：`{ "content_id", "state": "READY", "video_sha256" }`。

- 无本机 MP4（非 Android／编码失败）时 App 仅上传音频并轮询至 READY（或 FAILED 可 retry）
- 本机播放仍用 Indexed-MJPEG；MP4 仅用于云端存储与预览
