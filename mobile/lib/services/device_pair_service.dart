import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 设备配对目标：从硬件屏幕二维码解析得到。
class DevicePairTarget {
  const DevicePairTarget({
    required this.ip,
    required this.port,
    required this.nonce,
    this.deviceId,
  });

  final String ip;
  final int port;
  final String nonce;
  final String? deviceId;
}

class DevicePairException implements Exception {
  DevicePairException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// 扫码配对：解析硬件二维码，并通过局域网 HTTP 把 access token 传给硬件。
///
/// 二维码载荷格式：`SNDPOLA1|<ipv4>|<port>|<nonce>|<devid>`。
class DevicePairService {
  DevicePairService._();

  static const _magic = 'SNDPOLA1';
  static const _timeout = Duration(seconds: 8);

  /// 解析二维码原文；非配对码返回 null（调用方继续扫描）。
  static DevicePairTarget? parseQr(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;
    final parts = text.split('|');
    if (parts.length < 4 || parts[0] != _magic) return null;

    final ip = parts[1];
    final port = int.tryParse(parts[2]);
    final nonce = parts[3];
    if (port == null || port <= 0 || port > 65535) return null;
    if (nonce.isEmpty) return null;
    if (!_isIpv4(ip)) return null;

    return DevicePairTarget(
      ip: ip,
      port: port,
      nonce: nonce,
      deviceId: parts.length > 4 && parts[4].isNotEmpty ? parts[4] : null,
    );
  }

  /// 把 token 发送给硬件。成功返回；失败抛 [DevicePairException]。
  ///
  /// 使用原始 [Socket] 而非 package:http：嵌入式设备在回完响应后会立即关闭
  /// 连接（常以 TCP RST 而非优雅 FIN 结束），dart:io 的 HttpClient 会因此抛
  /// 异常并丢弃已收到的响应。这里手动发请求、读取已到达的字节并宽松解析状态
  /// 行——只要在连接断开前读到状态码即可判定结果。
  static Future<void> sendToken({
    required DevicePairTarget target,
    required String token,
    String? userId,
    String? email,
    String? serverUrl,
  }) async {
    final bodyBytes = utf8.encode(
      jsonEncode({
        'nonce': target.nonce,
        'token': token,
        'user_id': userId,
        'email': email,
        'server_url': serverUrl,
      }),
    );

    final Socket socket;
    try {
      socket = await Socket.connect(target.ip, target.port, timeout: _timeout);
    } catch (_) {
      throw DevicePairException('无法连接设备，请确认手机与设备在同一 WiFi');
    }

    final request = 'POST /pair HTTP/1.1\r\n'
        'Host: ${target.ip}:${target.port}\r\n'
        'Content-Type: application/json\r\n'
        'Content-Length: ${bodyBytes.length}\r\n'
        'Connection: close\r\n'
        '\r\n';

    final received = BytesBuilder(copy: false);
    try {
      socket.add(utf8.encode(request));
      socket.add(bodyBytes);
      await socket.flush();
      await socket.timeout(_timeout).forEach(received.add);
    } catch (_) {
      // 设备可能在回包后立即 RST/关闭连接；只要已收到响应字节即可继续解析。
    } finally {
      socket.destroy();
    }

    final raw = utf8.decode(received.toBytes(), allowMalformed: true);
    final code = _parseStatusCode(raw);
    if (code == null) {
      throw DevicePairException('无法连接设备，请确认手机与设备在同一 WiFi');
    }
    if (code == 200) return;
    if (code == 401) {
      throw DevicePairException(
        '二维码已过期或已使用，请在设备上刷新后重试',
        statusCode: 401,
      );
    }
    if (code == 403) {
      throw DevicePairException('设备未开启配对', statusCode: 403);
    }
    if (code == 400) {
      throw DevicePairException('请求被设备拒绝（参数无效）', statusCode: 400);
    }
    throw DevicePairException('配对失败（$code）', statusCode: code);
  }

  /// 从原始 HTTP 响应里解析状态码（状态行形如 `HTTP/1.1 200 OK`）。
  static int? _parseStatusCode(String response) {
    if (response.isEmpty) return null;
    final lineEnd = response.indexOf('\r\n');
    final statusLine = lineEnd >= 0 ? response.substring(0, lineEnd) : response;
    final parts = statusLine.split(' ');
    if (parts.length < 2 || !parts[0].startsWith('HTTP/')) return null;
    return int.tryParse(parts[1]);
  }

  static bool _isIpv4(String ip) {
    final octets = ip.split('.');
    if (octets.length != 4) return false;
    for (final o in octets) {
      final v = int.tryParse(o);
      if (v == null || v < 0 || v > 255) return false;
    }
    return true;
  }
}
