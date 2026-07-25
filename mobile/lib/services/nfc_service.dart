import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:android_intent_plus/android_intent.dart';
import 'package:ndef_record/ndef_record.dart' show NdefMessage, NdefRecord, TypeNameFormat;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

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

  /// 读取出厂声片档案；无正式记录时用 tagId 派生演示档案（仅开发）。
  Future<DiscFactoryProfile?> readFactoryProfile(
    NfcTag tag, {
    bool allowDemoFallback = true,
  }) async {
    final message = await _readMessage(tag) ?? _cachedMessage(tag);
    if (message != null) {
      final factory = _parseFactory(message);
      if (factory != null) {
        if (!factory.isAuthentic) {
          throw StateError('声片防伪校验失败');
        }
        return factory;
      }
    }
    if (!allowDemoFallback) return null;
    final tagId = tagIdHex(tag);
    final demo = DiscFactoryProfile.demoFromTagId(tagId);
    if (!demo.isAuthentic) {
      throw StateError('声片防伪校验失败');
    }
    return demo;
  }

  Future<bool> canWriteTag(NfcTag tag) async {
    if (await readBinding(tag) != null) return false;
    return _isWritable(tag);
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
    for (final record in message.records) {
      if (record.typeNameFormat == TypeNameFormat.media &&
          utf8.decode(record.type) == soundpolaMimeType) {
        try {
          final json =
              jsonDecode(utf8.decode(record.payload)) as Map<String, dynamic>;
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
    }
    return null;
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
  }) async {
    final writable = await _isWritable(tag);
    if (!writable) {
      throw StateError('该声片不可写入');
    }
    final binding = NfcBinding(
      soundId: soundId,
      discId: discId,
      title: title,
      contentId: contentId,
      nfcUrl: nfcUrl,
      rarity: rarity,
      series: series,
    );
    final records = <NdefRecord>[];

    final factoryRecord = factory?.copyWith(bound: true) ??
        (rarity != null
            ? DiscFactoryProfile(
                discId: discId,
                rarity: rarity,
                series: series ?? 'Unknown',
                signature: DiscFactoryProfile.computeSignature(
                  discId: discId,
                  rarity: rarity,
                  series: series ?? 'Unknown',
                  demo: true,
                ),
                bound: true,
                demo: true,
              )
            : null);
    if (factoryRecord != null) {
      records.add(
        NdefRecord(
          typeNameFormat: TypeNameFormat.media,
          type: Uint8List.fromList(utf8.encode(soundpolaFactoryMimeType)),
          identifier: Uint8List(0),
          payload: Uint8List.fromList(
            utf8.encode(jsonEncode(factoryRecord.toJson())),
          ),
        ),
      );
    }

    records.add(
      NdefRecord(
        typeNameFormat: TypeNameFormat.media,
        type: Uint8List.fromList(utf8.encode(soundpolaMimeType)),
        identifier: Uint8List(0),
        payload: Uint8List.fromList(utf8.encode(jsonEncode(binding.toJson()))),
      ),
    );
    // Prefer URI for Trigger boards that resolve nfc_url; keep text fallback.
    final uri = nfcUrl;
    if (uri != null && uri.isNotEmpty) {
      records.add(
        NdefRecord(
          typeNameFormat: TypeNameFormat.wellKnown,
          type: Uint8List.fromList([0x55]), // 'U'
          identifier: Uint8List(0),
          payload: _encodeUriPayload(uri),
        ),
      );
    }
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
    await _writeMessage(tag, NdefMessage(records: records));
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
