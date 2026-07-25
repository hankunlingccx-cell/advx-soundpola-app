# AdventureX Cloud Media 对接说明

契约文件：[`openapi-cloud-media.yaml`](./openapi-cloud-media.yaml)

预设基址：`http://soundpola.babelbeast.com:9000`（可在登录页「服务器设置」改写）

## 运行

```powershell
cd mobile
flutter run -d 53740dd4
```

## 联调流程

1. 登录 / 注册后会自动签发并保存 UserToken。
2. Press 会上传 Draft 本地音频 → 轮询 READY → 写入 NFC（`contentId` + `nfc_url`）。
3. Collection 下拉刷新可重新 `listOwnedContents`。

# 上传协议（App 已对齐）

```http
POST /api/v1/contents
Authorization: Bearer <USER_TOKEN>
Content-Type: multipart/form-data; boundary=...
```

- 文件字段名必须是 **`audio`**
- 不要手写死 `Content-Type: multipart/form-data`（须带 boundary，由客户端自动生成）
- 成功：`201` + `content_id` / `state=UPLOADED` / `status_url`

等价 curl：

```bash
curl -i \
  -X POST \
  -H "Authorization: Bearer $USER_TOKEN" \
  -F "audio=@recording.m4a" \
  http://soundpola.babelbeast.com:9000/api/v1/contents
```
