import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:android_intent_plus/android_intent.dart';
import 'package:ndef_record/ndef_record.dart' show NdefMessage, NdefRecord, TypeNameFormat;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

import '../cloud/cloud_media_config.dart';
import '../data/disc_rarity.dart';

const soundpolaMimeType = 'application/vnd.soundpola+json';
const soundpolaFactoryMimeType = 'application/vnd.soundpola.factory+json';

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
    this.rarity,
    this.series,
  });

  final String soundId;
  final String discId;
  final String title;
  /// Cloud Media content id (32-hex) for Trigger `GET /c/{content_id}`.
  final String? contentId;
  /// Absolute NFC resolve URL from ContentSummary.nfc_url when READY.
  final String? nfcUrl;
  final DiscRarity? rarity;
  final String? series;

  Map<String, dynamic> toJson() => {
        'v': 3,
        'soundId': soundId,
        'discId': discId,
        'title': title,
        if (contentId != null) 'contentId': contentId,
        if (nfcUrl != null) 'nfcUrl': nfcUrl,
        if (rarity != null) 'rarity': rarity!.code,
        if (series != null) 'series': series,
      };

  /// Compact payload for small NTAG capacity.
  Map<String, dynamic> toCompactJson() => {
        'v': 3,
        'soundId': soundId,
        'discId': discId,
        if (contentId != null) 'contentId': contentId,
        if (rarity != null) 'rarity': rarity!.code,
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
      rarity: DiscRarity.tryParse(json['rarity'] as String?),
      series: json['series'] as String? ?? json['batch'] as String?,
    );
  }
}

/// One-shot inspection (single NDEF read) before writing.
class NfcTagInspection {
  const NfcTagInspection({
    required this.writable,
    this.binding,
    this.factory,
    this.maxNdefBytes,
    this.existingFactoryOnTag = false,
  });

  final bool writable;
  final NfcBinding? binding;
  final DiscFactoryProfile? factory;
  final int? maxNdefBytes;
  final bool existingFactoryOnTag;
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
    final tail = compact.length > 4
        ? compact.substring(compact.length - 4)
        : compact.padLeft(4, '0');
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

  /// Single I/O pass: read NDEF once, resolve binding / factory / capacity.
  /// Prefer this over chaining [readBinding] + [canWriteTag] + [readFactoryProfile].
  Future<NfcTagInspection> inspectTag(
    NfcTag tag, {
    bool allowDemoFallback = true,
  }) async {
    NdefMessage? message;
    try {
      message = await _readMessage(tag);
    } catch (_) {
      message = null;
    }
    message ??= _cachedMessage(tag);

    final binding = message != null ? _parseBinding(message) : null;
    var factory = message != null ? _parseFactory(message) : null;
    final hadFactory = factory != null;
    if (factory != null && !factory.isAuthentic) {
      throw StateError('声片防伪校验失败');
    }
    if (factory == null && allowDemoFallback) {
      final demo = DiscFactoryProfile.demoFromTagId(tagIdHex(tag));
      if (!demo.isAuthentic) {
        throw StateError('声片防伪校验失败');
      }
      factory = demo;
    }

    final writable = await _isWritable(tag);
    return NfcTagInspection(
      writable: writable && binding == null && !(factory?.bound ?? false),
      binding: binding,
      factory: factory,
      maxNdefBytes: _maxNdefBytes(tag),
      existingFactoryOnTag: hadFactory,
    );
  }

  int? _maxNdefBytes(NfcTag tag) {
    if (Platform.isAndroid) {
      return NdefAndroid.from(tag)?.maxSize;
    }
    return null;
  }

  /// 读取出厂声片档案；无正式记录时用 tagId 派生演示档案（仅开发）。
  Future<DiscFactoryProfile?> readFactoryProfile(
    NfcTag tag, {
    bool allowDemoFallback = true,
  }) async {
    final snap = await inspectTag(tag, allowDemoFallback: allowDemoFallback);
    return snap.factory;
  }

  Future<bool> canWriteTag(NfcTag tag) async {
    final snap = await inspectTag(tag);
    return snap.writable;
  }

  NdefMessage? _cachedMessage(NfcTag tag) {
    if (Platform.isAndroid) return NdefAndroid.from(tag)?.cachedNdefMessage;
    if (Platform.isIOS) return NdefIos.from(tag)?.cachedNdefMessage;
    return null;
  }

  DiscFactoryProfile? _parseFactory(NdefMessage message) {
    for (final record in message.records) {
      if (record.typeNameFormat == TypeNameFormat.media &&
          utf8.decode(record.type) == soundpolaFactoryMimeType) {
        try {
          final json =
              jsonDecode(utf8.decode(record.payload)) as Map<String, dynamic>;
          return DiscFactoryProfile.fromJson(json);
        } catch (_) {}
      }
    }
    return null;
  }

  NfcBinding? _parseBinding(NdefMessage message) {
    NfcBinding? fromUri;
    for (final record in message.records) {
      if (record.typeNameFormat == TypeNameFormat.media &&
          utf8.decode(record.type) == soundpolaMimeType) {
        try {
          final json =
              jsonDecode(utf8.decode(record.payload)) as Map<String, dynamic>;
          final parsed = NfcBinding.fromJson(json);
          if (parsed != null) return parsed;
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
      // Slim writes may be URI-only (`/c/{contentId}`); still counts as written.
      if (fromUri == null &&
          record.typeNameFormat == TypeNameFormat.wellKnown &&
          record.type.isNotEmpty &&
          record.type[0] == 0x55) {
        fromUri = _bindingFromUriPayload(record.payload);
      }
    }
    return fromUri;
  }

  /// Treat SoundPola content deep links as an existing write (no overwrite).
  NfcBinding? _bindingFromUriPayload(Uint8List payload) {
    final uri = _decodeUriPayload(payload);
    if (uri == null || uri.isEmpty) return null;
    final contentId = _contentIdFromResolveUri(uri);
    if (contentId == null) return null;
    return NfcBinding(
      soundId: '',
      discId: '',
      title: '',
      contentId: contentId,
      nfcUrl: uri,
    );
  }

  String? _decodeUriPayload(Uint8List payload) {
    if (payload.isEmpty) return null;
    const prefixes = <String>[
      '',
      'http://www.',
      'https://www.',
      'http://',
      'https://',
      'tel:',
      'mailto:',
      'ftp://anonymous:anonymous@',
      'ftp://ftp.',
      'ftps://',
      'sftp://',
      'smb://',
      'nfs://',
      'ftp://',
      'dav://',
      'news:',
      'telnet://',
      'imap:',
      'rtsp://',
      'urn:',
      'pop:',
      'sip:',
      'sips:',
      'tftp:',
      'btspp://',
      'btl2cap://',
      'btgoep://',
      'tcpobex://',
      'irdaobex://',
      'file://',
      'urn:epc:id:',
      'urn:epc:tag:',
      'urn:epc:pat:',
      'urn:epc:raw:',
      'urn:epc:',
      'urn:nfc:',
    ];
    final code = payload[0];
    final remainder = utf8.decode(payload.sublist(1), allowMalformed: true);
    if (code < 0 || code >= prefixes.length) return remainder;
    return '${prefixes[code]}$remainder';
  }

  /// `http(s)://{host}/c/{32hex}` or `soundpola://c/{32hex}`.
  String? _contentIdFromResolveUri(String uri) {
    final normalized = uri.trim();
    final match = RegExp(
      r'(?:soundpola://c/|/c/)([0-9a-fA-F]{32})(?:[/?#]|$)',
      caseSensitive: false,
    ).firstMatch(normalized);
    return match?.group(1)?.toLowerCase();
  }

  String _decodeTextPayload(Uint8List payload) {
    if (payload.isEmpty) return '';
    final langLen = payload[0] & 0x3F;
    return utf8.decode(payload.sublist(1 + langLen));
  }

  Uint8List _encodeTextPayload(String text, {String lang = 'en'}) {
    final langBytes = utf8.encode(lang);
    final textBytes = utf8.encode(text);
    return Uint8List.fromList([langBytes.length, ...langBytes, ...textBytes]);
  }

  Future<void> writeBinding({
    required NfcTag tag,
    required String soundId,
    required String discId,
    required String title,
    String? contentId,
    String? nfcUrl,
    DiscRarity? rarity,
    String? series,
    DiscFactoryProfile? factory,
    bool existingFactoryOnTag = false,
    int? maxNdefBytes,
  }) async {
    final snap = await inspectTag(tag);
    if (snap.binding != null || (snap.factory?.bound ?? false)) {
      throw StateError('该声片已写入');
    }
    if (!snap.writable) {
      throw StateError('该声片不可写入');
    }
    final linkUrl = (contentId != null && contentId.isNotEmpty)
        ? '${CloudMediaConfig.baseUrl}/c/$contentId'
        : ((nfcUrl != null && nfcUrl.isNotEmpty) ? nfcUrl : null);
    final binding = NfcBinding(
      soundId: soundId,
      discId: discId,
      title: title,
      contentId: contentId,
      nfcUrl: linkUrl ?? nfcUrl,
      rarity: rarity,
      series: series,
    );

    final capacity = maxNdefBytes ?? snap.maxNdefBytes;

    final hadFactoryOnTag = existingFactoryOnTag || snap.existingFactoryOnTag;

    // Prefer slim message: small tags (NTAG213 ~144B) cannot hold full MIME set.
    // Demo rarity can still be derived from tagId on read; only rewrite factory
    // when it already exists on the tag (update bound flag).
    final factoryToWrite = hadFactoryOnTag && factory != null
        ? factory.copyWith(bound: true)
        : null;

    List<NdefRecord> build({
      required bool includeFactory,
      required bool compactBinding,
      required bool includeUri,
      required bool includeText,
      required bool includeMimeBinding,
    }) {
      final records = <NdefRecord>[];
      // URI first: system NFC readers / tap-to-open match Well-Known 'U'.
      if (includeUri && linkUrl != null && linkUrl.isNotEmpty) {
        records.add(
          NdefRecord(
            typeNameFormat: TypeNameFormat.wellKnown,
            type: Uint8List.fromList([0x55]), // 'U'
            identifier: Uint8List(0),
            payload: _encodeUriPayload(linkUrl),
          ),
        );
      }
      if (includeFactory && factoryToWrite != null) {
        records.add(
          NdefRecord(
            typeNameFormat: TypeNameFormat.media,
            type: Uint8List.fromList(utf8.encode(soundpolaFactoryMimeType)),
            identifier: Uint8List(0),
            payload: Uint8List.fromList(
              utf8.encode(jsonEncode(factoryToWrite.toJson())),
            ),
          ),
        );
      }
      if (includeMimeBinding) {
        final json = compactBinding
            ? binding.toCompactJson()
            : binding.toJson();
        records.add(
          NdefRecord(
            typeNameFormat: TypeNameFormat.media,
            type: Uint8List.fromList(utf8.encode(soundpolaMimeType)),
            identifier: Uint8List(0),
            payload: Uint8List.fromList(utf8.encode(jsonEncode(json))),
          ),
        );
      }
      if (includeText) {
        final textPayload = contentId != null && contentId.isNotEmpty
            ? 'SOUNDPOLA:$soundId:$discId:$contentId'
            : 'SOUNDPOLA:$soundId:$discId';
        records.add(
          NdefRecord(
            typeNameFormat: TypeNameFormat.wellKnown,
            type: Uint8List.fromList([0x54]),
            identifier: Uint8List(0),
            payload: _encodeTextPayload(textPayload),
          ),
        );
      }
      return records;
    }

    // Candidate payloads from richest → leanest.
    final candidates = <List<NdefRecord>>[
      build(
        includeFactory: true,
        compactBinding: false,
        includeUri: true,
        includeText: true,
        includeMimeBinding: true,
      ),
      build(
        includeFactory: hadFactoryOnTag,
        compactBinding: true,
        includeUri: true,
        includeText: true,
        includeMimeBinding: true,
      ),
      build(
        includeFactory: false,
        compactBinding: true,
        includeUri: true,
        includeText: true,
        includeMimeBinding: true,
      ),
      build(
        includeFactory: false,
        compactBinding: true,
        includeUri: true,
        includeText: true,
        includeMimeBinding: false,
      ),
      build(
        includeFactory: false,
        compactBinding: true,
        includeUri: true,
        includeText: false,
        includeMimeBinding: false,
      ),
    ];

    List<NdefRecord>? chosen;
    for (final records in candidates) {
      if (records.isEmpty) continue;
      final size = _estimateNdefSize(records);
      if (capacity == null || size <= capacity) {
        chosen = records;
        break;
      }
    }
    if (chosen == null) {
      throw StateError(
        '声片存储空间不足（约需写入云端链接）。请使用容量更大的 SoundPola 声片。',
      );
    }

    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(milliseconds: 140 * attempt));
        }
        await _writeMessage(tag, NdefMessage(records: chosen));
        return;
      } catch (e) {
        lastError = e;
        final blob = e.toString().toLowerCase();
        final lost = blob.contains('tag') ||
            blob.contains('ioexception') ||
            blob.contains('lost') ||
            blob.contains('abort');
        if (!lost || attempt == 2) rethrow;
      }
    }
    throw lastError ?? StateError('写入失败');
  }

  /// Rough NDEF message byte length (Android user-memory oriented).
  int _estimateNdefSize(List<NdefRecord> records) {
    var total = 2; // NDEF + terminator TLV overhead approx
    for (final r in records) {
      total += 2 + r.type.length + r.payload.length + r.identifier.length + 4;
    }
    return total;
  }

  /// NDEF URI RTD payload: 1-byte identifier code + UTF-8 remainder.
  ///
  /// Expected NFC Tools display for `http://host/...` is
  /// `Record 1 - http://` with remainder only — requires code `0x03`,
  /// not `0x00` (full URI, which many readers fail to open).
  Uint8List _encodeUriPayload(String uri) {
    // NFC Forum URI Record Type Definition (longest match wins).
    const prefixes = <String>[
      '', // 0x00 — no abbreviation
      'http://www.', // 0x01
      'https://www.', // 0x02
      'http://', // 0x03
      'https://', // 0x04
      'tel:', // 0x05
      'mailto:', // 0x06
      'ftp://anonymous:anonymous@', // 0x07
      'ftp://ftp.', // 0x08
      'ftps://', // 0x09
      'sftp://', // 0x0A
      'smb://', // 0x0B
      'nfs://', // 0x0C
      'ftp://', // 0x0D
      'dav://', // 0x0E
      'news:', // 0x0F
      'telnet://', // 0x10
      'imap:', // 0x11
      'rtsp://', // 0x12
      'urn:', // 0x13
      'pop:', // 0x14
      'sip:', // 0x15
      'sips:', // 0x16
      'tftp:', // 0x17
      'btspp://', // 0x18
      'btl2cap://', // 0x19
      'btgoep://', // 0x1A
      'tcpobex://', // 0x1B
      'irdaobex://', // 0x1C
      'file://', // 0x1D
      'urn:epc:id:', // 0x1E
      'urn:epc:tag:', // 0x1F
      'urn:epc:pat:', // 0x20
      'urn:epc:raw:', // 0x21
      'urn:epc:', // 0x22
      'urn:nfc:', // 0x23
    ];

    var code = 0;
    var remainder = uri;
    for (var i = 1; i < prefixes.length; i++) {
      final p = prefixes[i];
      if (p.isEmpty) continue;
      if (uri.length >= p.length &&
          uri.substring(0, p.length).toLowerCase() == p.toLowerCase() &&
          p.length > prefixes[code].length) {
        code = i;
        remainder = uri.substring(p.length);
      }
    }
    return Uint8List.fromList([code, ...utf8.encode(remainder)]);
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
