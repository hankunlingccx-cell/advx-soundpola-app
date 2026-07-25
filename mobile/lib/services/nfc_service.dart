import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:android_intent_plus/android_intent.dart';
import 'package:ndef_record/ndef_record.dart' show NdefMessage, NdefRecord, TypeNameFormat;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
import '../cloud/cloud_media_config.dart';

const soundpolaMimeType = 'application/vnd.soundpola+json';

enum NfcDeviceStatus {
  available,
  unavailable,
  disabled,
}

class NfcBinding {
  const NfcBinding({
    required this.soundId,
    required this.discId,
    required this.title,
    this.contentId,
    this.nfcUrl,
  });

  final String soundId;
  final String discId;
  final String title;
  /// Cloud Media content id (32-hex) for Trigger `GET /c/{content_id}`.
  final String? contentId;
  /// Absolute NFC resolve URL from ContentSummary.nfc_url when READY.
  final String? nfcUrl;

  Map<String, dynamic> toJson() => {
        'v': 2,
        'soundId': soundId,
        'discId': discId,
        'title': title,
        if (contentId != null) 'contentId': contentId,
        if (nfcUrl != null) 'nfcUrl': nfcUrl,
      };

  static NfcBinding? fromJson(Map<String, dynamic> json) {
    final soundId = json['soundId'] as String?;
    final discId = json['discId'] as String?;
    if (soundId == null || discId == null) return null;
    return NfcBinding(
      soundId: soundId,
      discId: discId,
      title: json['title'] as String? ?? '',
      contentId: json['contentId'] as String? ?? json['content_id'] as String?,
      nfcUrl: json['nfcUrl'] as String? ?? json['nfc_url'] as String?,
    );
  }
}

class NfcService {
  NfcService._();
  static final NfcService instance = NfcService._();

  Future<NfcDeviceStatus> checkStatus() async {
    final availability = await NfcManager.instance.checkAvailability();
    return switch (availability) {
      NfcAvailability.enabled => NfcDeviceStatus.available,
      NfcAvailability.disabled => NfcDeviceStatus.disabled,
      NfcAvailability.unsupported => NfcDeviceStatus.unavailable,
    };
  }

  Future<void> openNfcSettings() async {
    if (!Platform.isAndroid) return;
    const AndroidIntent(action: 'android.settings.NFC_SETTINGS').launch();
  }

  String tagIdHex(NfcTag tag) {
    if (Platform.isAndroid) {
      final androidTag = NfcTagAndroid.from(tag);
      if (androidTag != null) {
        return androidTag.id
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toUpperCase();
      }
    }
    return tag.hashCode.toRadixString(16).toUpperCase();
  }

  String generateDiscId(String tagIdHex) {
    final now = DateTime.now();
    final compact = tagIdHex.replaceAll(':', '');
    final tail = compact.length > 4 ? compact.substring(compact.length - 4) : compact.padLeft(4, '0');
    return 'SP-${now.year}-${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-$tail';
  }

  Future<NfcBinding?> readBinding(NfcTag tag) async {
    final message = await _readMessage(tag);
    if (message != null) {
      final parsed = _parseBinding(message);
      if (parsed != null) return parsed;
    }
    if (Platform.isAndroid) {
      final cached = NdefAndroid.from(tag)?.cachedNdefMessage;
      if (cached != null) return _parseBinding(cached);
    }
    if (Platform.isIOS) {
      final cached = NdefIos.from(tag)?.cachedNdefMessage;
      if (cached != null) return _parseBinding(cached);
    }
    return null;
  }

  Future<bool> canWriteTag(NfcTag tag) async {
    if (await readBinding(tag) != null) return false;
    return _isWritable(tag);
  }

  NfcBinding? _parseBinding(NdefMessage message) {
    for (final record in message.records) {
      if (record.typeNameFormat == TypeNameFormat.media &&
          utf8.decode(record.type) == soundpolaMimeType) {
        try {
          final json = jsonDecode(utf8.decode(record.payload)) as Map<String, dynamic>;
          return NfcBinding.fromJson(json);
        } catch (_) {}
      }
      if (record.typeNameFormat == TypeNameFormat.wellKnown &&
          record.type.isNotEmpty &&
          record.type[0] == 0x54) {
        final text = _decodeTextPayload(record.payload);
        if (text.startsWith('SOUNDPOLA:')) {
          final parts = text.split(':');
          if (parts.length >= 3) {
            return NfcBinding(
              soundId: parts[1],
              discId: parts[2],
              title: '',
              contentId: parts.length >= 4 ? parts[3] : null,
            );
          }
        }
      }
      // URI-only tags (Option E): match /c/<32-hex> and treat as bound.
      if (record.typeNameFormat == TypeNameFormat.wellKnown &&
          record.type.isNotEmpty &&
          record.type[0] == 0x55) {
        final uri = _decodeUriPayload(record.payload);
        final contentId = _extractContentId(uri);
        if (contentId != null) {
          return NfcBinding(
            soundId: '',
            discId: contentId,
            title: '',
            contentId: contentId,
            nfcUrl: uri,
          );
        }
      }
    }
    return null;
  }

  String _decodeUriPayload(Uint8List payload) {
    if (payload.isEmpty) return '';
    // First byte is the URI abbreviation prefix code; 0x00 = no abbreviation.
    const prefixes = <String>[
      '', 'http://www.', 'https://www.', 'http://', 'https://',
      'tel:', 'mailto:', 'ftp://anonymous:anonymous@', 'ftp://ftp.',
      'ftps://', 'sftp://', 'smb://', 'nfs://', 'ftp://', 'dav://',
      'news:', 'telnet://', 'imap:', 'rtsp://', 'urn:', 'pop:',
      'sip:', 'sips:', 'tftp:', 'btspp://', 'btl2cap://', 'btgoep://',
      'tcpobex://', 'irdaobex://', 'file://', 'urn:epc:id:',
      'urn:epc:tag:', 'urn:epc:pat:', 'urn:epc:raw:', 'urn:epc:', 'urn:nfc:',
    ];
    final code = payload[0];
    final prefix = code < prefixes.length ? prefixes[code] : '';
    return prefix + utf8.decode(payload.sublist(1));
  }

  String? _extractContentId(String uri) {
    final match = RegExp(r'/c/([0-9a-fA-F]{32})').firstMatch(uri);
    return match?.group(1);
  }

  String _decodeTextPayload(Uint8List payload) {
    if (payload.isEmpty) return '';
    final langLen = payload[0] & 0x3F;
    return utf8.decode(payload.sublist(1 + langLen));
  }

  Future<void> writeBinding({
    required NfcTag tag,
    required String soundId,
    required String discId,
    required String title,
    String? contentId,
    String? nfcUrl,
  }) async {
    final writable = await _isWritable(tag);
    if (!writable) {
      throw StateError('该声片不可写入');
    }
    // Always compose from the currently configured login server IP:port so
    // the written URL is a browser-openable absolute link. A server-provided
    // nfcUrl is only used as a last-resort fallback (may be a different host).
    final linkUrl = (contentId != null && contentId.isNotEmpty)
        ? '${CloudMediaConfig.baseUrl}/c/$contentId'
        : ((nfcUrl != null && nfcUrl.isNotEmpty) ? nfcUrl : null);
    if (linkUrl == null || linkUrl.isEmpty) {
      throw StateError('缺少解析链接，无法写入声片');
    }
    // Option E: write only the URI record. All metadata is resolved from cloud
    // via GET /c/<contentId>. Keeps the payload ~50-80B so NTAG213 fits.
    final uriRecord = NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: Uint8List.fromList([0x55]), // 'U'
      identifier: Uint8List(0),
      payload: _encodeUriPayload(linkUrl),
    );
    final message = NdefMessage(records: [uriRecord]);
    final capacity = await _maxSize(tag);
    if (capacity != null && capacity > 0) {
      final size = _encodedMessageSize(message);
      if (size > capacity) {
        throw StateError('声片容量不足（$capacity B / 需要 $size B）');
      }
    }
    await _writeMessageWithRetry(tag, message);
  }

  int _encodedMessageSize(NdefMessage message) {
    var total = 0;
    for (final r in message.records) {
      // NDEF record overhead: header(1) + typeLen(1) + payloadLen(1 or 4)
      final payloadLen = r.payload.length;
      final overhead = 3 + (payloadLen > 255 ? 3 : 0) +
          (r.identifier.isNotEmpty ? 1 + r.identifier.length : 0);
      total += overhead + r.type.length + payloadLen;
    }
    return total;
  }

  Future<int?> _maxSize(NfcTag tag) async {
    if (Platform.isAndroid) {
      final ndef = NdefAndroid.from(tag);
      return ndef?.maxSize;
    }
    if (Platform.isIOS) {
      final ndef = NdefIos.from(tag);
      if (ndef == null) return null;
      try {
        final status = await ndef.queryNdefStatus();
        return status.capacity;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> _writeMessageWithRetry(
    NfcTag tag,
    NdefMessage message, {
    int attempts = 3,
  }) async {
    Object? lastError;
    for (var i = 0; i < attempts; i++) {
      try {
        await _writeMessage(tag, message);
        return;
      } catch (e) {
        lastError = e;
        if (i < attempts - 1) {
          await Future.delayed(const Duration(milliseconds: 220));
        }
      }
    }
    throw lastError ?? StateError('声片写入失败');
  }

  /// NDEF URI payload: code 0x00 = full URI in UTF-8 (no abbreviation).
  Uint8List _encodeUriPayload(String uri) {
    final bytes = utf8.encode(uri);
    return Uint8List.fromList([0x00, ...bytes]);
  }

  Future<NdefMessage?> _readMessage(NfcTag tag) async {
    if (Platform.isAndroid) {
      final ndef = NdefAndroid.from(tag);
      if (ndef == null) return null;
      return ndef.getNdefMessage();
    }
    if (Platform.isIOS) {
      final ndef = NdefIos.from(tag);
      if (ndef == null) return null;
      return ndef.readNdef();
    }
    return null;
  }

  Future<bool> _isWritable(NfcTag tag) async {
    if (Platform.isAndroid) {
      final ndef = NdefAndroid.from(tag);
      return ndef?.isWritable ?? false;
    }
    if (Platform.isIOS) {
      final ndef = NdefIos.from(tag);
      if (ndef == null) return false;
      final status = await ndef.queryNdefStatus();
      return status.status == NdefStatusIos.readWrite;
    }
    return false;
  }

  Future<void> _writeMessage(NfcTag tag, NdefMessage message) async {
    if (Platform.isAndroid) {
      final ndef = NdefAndroid.from(tag);
      if (ndef == null) throw StateError('未识别到可写入的 NDEF 声片');
      await ndef.writeNdefMessage(message);
      return;
    }
    if (Platform.isIOS) {
      final ndef = NdefIos.from(tag);
      if (ndef == null) throw StateError('未识别到可写入的 NDEF 声片');
      await ndef.writeNdef(message);
      return;
    }
    throw UnsupportedError('当前平台不支持 NFC 写入');
  }

  Future<void> startSession({
    required void Function(NfcTag tag) onDiscovered,
    String alertMessage = '将手机背面靠近声片',
    bool invalidateAfterFirstRead = false,
  }) async {
    await NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      alertMessageIos: alertMessage,
      invalidateAfterFirstReadIos: invalidateAfterFirstRead,
      onDiscovered: onDiscovered,
    );
  }

  Future<void> stopSession({String? message, String? error}) =>
      NfcManager.instance.stopSession(
        alertMessageIos: error == null ? message : null,
        errorMessageIos: error,
      );
}
