# AdventureX Cloud Media 对接说明

契约文件：[`openapi-cloud-media.yaml`](./openapi-cloud-media.yaml)

预设基址：`https://soundpola.babelbeast.com`（可在登录页「服务器设置」改写）

## 运行

```powershell
cd mobile
flutter run -d 53740dd4
```

## 联调流程

1. 登录 / 注册后会自动签发并保存 UserToken。
2. Press：上传 Draft 本地音频 → 本机 bake 导出 H.264 MP4 → 上传视频 → 内容 `READY` → 写入 NFC（`contentId` + `nfc_url`）。
3. READY 后公开预览：`/preview/{content_id}/video`、`/preview/{content_id}/audio`。
4. Collection 下拉刷新可重新 `listOwnedContents`。

# 上传协议（App 已对齐）

两步上传：

## 1) 上传音频

```http
POST /api/v1/contents
Authorization: Bearer <USER_TOKEN>
Content-Type: multipart/form-data; boundary=...
```

- 文件字段名必须是 **`audio`**
- 不要手写死 `Content-Type: multipart/form-data`（须带 boundary，由客户端自动生成）
- 成功：`201` + `content_id` / `state=UPLOADED` / `status_url`

## 2) 上传可视化视频（本机 bake → MP4）

```http
POST /api/v1/contents/{content_id}/video
Authorization: Bearer <USER_TOKEN>
Content-Type: multipart/form-data; boundary=...
```

- 文件字段名必须是 **`video`**（H.264 MP4，如 `visualization.mp4`）
- 成功：`200/201` + `content_id` / `state=READY` / `video_sha256`
- App：Indexed-MJPEG bake 就绪后硬件编码为 `visual.mp4` 再上传；导出或上传失败时保留已上传音频（不阻断 Press）

等价 curl：

```bash
TOKEN=$(curl -s -X POST https://soundpola.babelbeast.com/api/v1/sessions \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"yourpass"}' \
  | python -c "import sys,json;print(json.load(sys.stdin)['token'])")

CONTENT_ID=$(curl -s -X POST https://soundpola.babelbeast.com/api/v1/contents \
  -H "Authorization: Bearer $TOKEN" \
  -F "audio=@/path/to/audio.mp3" \
  | python -c "import sys,json;print(json.load(sys.stdin)['content_id'])")

curl -X POST "https://soundpola.babelbeast.com/api/v1/contents/$CONTENT_ID/video" \
  -H "Authorization: Bearer $TOKEN" \
  -F "video=@/path/to/visualization.mp4"
```
