import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../cloud/cloud_media_models.dart';
import '../services/visual_shape_service.dart';

enum SoundStatus {
  drafted,
  writing,
  cloudReady,
  writeFailed,
  chainPending,
  chainFailed,
  chainReady,
  collected,
}

class SoundMemory {
  SoundMemory({
    String? id,
    required this.title,
    required this.category,
    this.description = '',
    required this.durationSec,
    DateTime? recordedAt,
    this.locationLabel = '地点未记录',
    this.deviceLabel = 'Mobile Device',
    this.status = SoundStatus.drafted,
    int? visualSeed,
    this.discId,
    this.assetId,
    this.audioPath,
    this.nfcTagId,
    this.pressedAt,
    this.chainedAt,
    this.networkLabel = 'Injective inEVM Testnet',
    this.contractLabel,
    this.tokenId,
    this.txHash,
    this.contentId,
    this.nfcUrl,
    this.cloudState,
    this.visualUrl,
    this.visualPath,
  })  : id = id ?? _newId(),
        recordedAt = recordedAt ?? DateTime.now(),
        visualSeed = visualSeed ?? DateTime.now().millisecondsSinceEpoch % 10000;

  static final _rng = Random();
  static String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toString() +
      _rng.nextInt(9999).toString().padLeft(4, '0');

  final String id;
  final String title;
  final String category;
  final String description;
  final int durationSec;
  final DateTime recordedAt;
  final String locationLabel;
  final String deviceLabel;
  final SoundStatus status;
  final int visualSeed;
  final String? discId;
  final String? assetId;
  final String? audioPath;
  final String? nfcTagId;
  final DateTime? pressedAt;
  final DateTime? chainedAt;
  final String networkLabel;
  final String? contractLabel;
  final String? tokenId;
  final String? txHash;
  /// Cloud Media content_id (32-hex).
  final String? contentId;
  final String? nfcUrl;
  /// Wire state: UPLOADED / PROCESSING / READY / FAILED / DELETED
  final String? cloudState;
  /// Remote URL of the 3D visual JSON (cloud-produced, re-fetchable).
  final String? visualUrl;
  /// Local cached path of the visual JSON: `<appDocs>/visuals/vis_<contentId>.json`.
  final String? visualPath;

  SoundMemory copyWith({
    String? title,
    String? category,
    String? description,
    SoundStatus? status,
    String? discId,
    String? assetId,
    String? audioPath,
    String? nfcTagId,
    DateTime? pressedAt,
    DateTime? chainedAt,
    String? networkLabel,
    String? contractLabel,
    String? tokenId,
    String? txHash,
    String? contentId,
    String? nfcUrl,
    String? cloudState,
    String? visualUrl,
    String? visualPath,
  }) {
    return SoundMemory(
      id: id,
      title: title ?? this.title,
      category: category ?? this.category,
      description: description ?? this.description,
      durationSec: durationSec,
      recordedAt: recordedAt,
      locationLabel: locationLabel,
      deviceLabel: deviceLabel,
      status: status ?? this.status,
      visualSeed: visualSeed,
      discId: discId ?? this.discId,
      assetId: assetId ?? this.assetId,
      audioPath: audioPath ?? this.audioPath,
      nfcTagId: nfcTagId ?? this.nfcTagId,
      pressedAt: pressedAt ?? this.pressedAt,
      chainedAt: chainedAt ?? this.chainedAt,
      networkLabel: networkLabel ?? this.networkLabel,
      contractLabel: contractLabel ?? this.contractLabel,
      tokenId: tokenId ?? this.tokenId,
      txHash: txHash ?? this.txHash,
      contentId: contentId ?? this.contentId,
      nfcUrl: nfcUrl ?? this.nfcUrl,
      cloudState: cloudState ?? this.cloudState,
      visualUrl: visualUrl ?? this.visualUrl,
      visualPath: visualPath ?? this.visualPath,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'description': description,
        'durationSec': durationSec,
        'recordedAt': recordedAt.toIso8601String(),
        'locationLabel': locationLabel,
        'deviceLabel': deviceLabel,
        'status': status.name,
        'visualSeed': visualSeed,
        if (discId != null) 'discId': discId,
        if (assetId != null) 'assetId': assetId,
        if (audioPath != null) 'audioPath': audioPath,
        if (nfcTagId != null) 'nfcTagId': nfcTagId,
        if (pressedAt != null) 'pressedAt': pressedAt!.toIso8601String(),
        if (chainedAt != null) 'chainedAt': chainedAt!.toIso8601String(),
        'networkLabel': networkLabel,
        if (contractLabel != null) 'contractLabel': contractLabel,
        if (tokenId != null) 'tokenId': tokenId,
        if (txHash != null) 'txHash': txHash,
        if (contentId != null) 'contentId': contentId,
        if (nfcUrl != null) 'nfcUrl': nfcUrl,
        if (cloudState != null) 'cloudState': cloudState,
        if (visualUrl != null) 'visualUrl': visualUrl,
        if (visualPath != null) 'visualPath': visualPath,
      };

  factory SoundMemory.fromJson(Map<String, dynamic> json) {
    SoundStatus parseStatus(String? name) {
      for (final s in SoundStatus.values) {
        if (s.name == name) return s;
      }
      return SoundStatus.drafted;
    }
    return SoundMemory(
      id: json['id'] as String?,
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? '其他',
      description: json['description'] as String? ?? '',
      durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
      recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? ''),
      locationLabel: json['locationLabel'] as String? ?? '地点未记录',
      deviceLabel: json['deviceLabel'] as String? ?? 'Mobile Device',
      status: parseStatus(json['status'] as String?),
      visualSeed: (json['visualSeed'] as num?)?.toInt(),
      discId: json['discId'] as String?,
      assetId: json['assetId'] as String?,
      audioPath: json['audioPath'] as String?,
      nfcTagId: json['nfcTagId'] as String?,
      pressedAt: json['pressedAt'] != null
          ? DateTime.tryParse(json['pressedAt'] as String)
          : null,
      chainedAt: json['chainedAt'] != null
          ? DateTime.tryParse(json['chainedAt'] as String)
          : null,
      networkLabel: json['networkLabel'] as String? ?? 'Injective inEVM Testnet',
      contractLabel: json['contractLabel'] as String?,
      tokenId: json['tokenId'] as String?,
      txHash: json['txHash'] as String?,
      contentId: json['contentId'] as String?,
      nfcUrl: json['nfcUrl'] as String?,
      cloudState: json['cloudState'] as String?,
      visualUrl: json['visualUrl'] as String?,
      visualPath: json['visualPath'] as String?,
    );
  }
}

const soundCategories = [
  '自然',
  '城市',
  '人声',
  '日常',
  '旅行',
  '特别时刻',
  '其他',
];

String formatDuration(int sec) {
  final m = sec ~/ 60;
  final s = sec % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String formatRecordedAt(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final mo = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final mi = dt.minute.toString().padLeft(2, '0');
  return '$y.$mo.$d  $h:$mi';
}

class SoundRepository extends ChangeNotifier {
  SoundRepository._();
  static final SoundRepository instance = SoundRepository._();

  static const _prefsKey = 'sp_sounds_v1';

  final List<SoundMemory> _sounds = [];
  bool _loaded = false;
  Timer? _saveDebounce;

  bool get isLoaded => _loaded;

  Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final entry in list) {
            if (entry is Map) {
              try {
                _sounds.add(SoundMemory.fromJson(
                  entry.map((k, v) => MapEntry(k.toString(), v)),
                ));
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint('SoundRepository load error: $e');
    }
    _loaded = true;
    unawaited(_pruneOrphanRecordings());
    unawaited(_pruneOrphanVisuals());
    notifyListeners();
  }

  void _schedulePersist() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _persistNow);
  }

  Future<void> _persistNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(_sounds.map((s) => s.toJson()).toList());
      await prefs.setString(_prefsKey, payload);
    } catch (e) {
      debugPrint('SoundRepository persist error: $e');
    }
  }

  Future<void> _pruneOrphanRecordings() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final rec = Directory('${dir.path}/recordings');
      if (!await rec.exists()) return;
      final referenced = _sounds
          .map((s) => s.audioPath)
          .whereType<String>()
          .toSet();
      final now = DateTime.now();
      await for (final entity in rec.list()) {
        if (entity is! File) continue;
        if (referenced.contains(entity.path)) continue;
        try {
          final stat = await entity.stat();
          if (now.difference(stat.modified).inHours < 1) continue;
          await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _pruneOrphanVisuals() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final vis = Directory('${dir.path}/visuals');
      if (!await vis.exists()) return;
      final referenced = _sounds
          .map((s) => s.visualPath)
          .whereType<String>()
          .toSet();
      final now = DateTime.now();
      await for (final entity in vis.list()) {
        if (entity is! File) continue;
        if (referenced.contains(entity.path)) continue;
        try {
          final stat = await entity.stat();
          if (now.difference(stat.modified).inHours < 1) continue;
          await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  List<SoundMemory> get sounds => List.unmodifiable(_sounds);

  List<SoundMemory> get drafts =>
      _sounds.where((s) => s.status != SoundStatus.collected).toList();

  List<SoundMemory> get collection =>
      _sounds.where((s) => s.status == SoundStatus.collected).toList();

  SoundMemory? get(String id) {
    try {
      return _sounds.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  SoundMemory? findByContentId(String contentId) {
    try {
      return _sounds.firstWhere((s) => s.contentId == contentId);
    } catch (_) {
      return null;
    }
  }

  void addDraft(SoundMemory memory) {
    _sounds.insert(0, memory.copyWith(status: SoundStatus.drafted));
    notifyListeners();
    _schedulePersist();
  }

  void update(String id, SoundMemory Function(SoundMemory) transform) {
    final index = _sounds.indexWhere((s) => s.id == id);
    if (index >= 0) {
      _sounds[index] = transform(_sounds[index]);
      notifyListeners();
      _schedulePersist();
    }
  }

  bool delete(String id) {
    final item = get(id);
    if (item == null) return false;
    if (item.status == SoundStatus.chainFailed ||
        item.status == SoundStatus.chainPending) {
      if (item.discId != null) return false;
    }
    final index = _sounds.indexWhere((s) => s.id == id);
    if (index < 0) return false;
    _sounds.removeAt(index);
    if (item.audioPath != null) {
      unawaited(_deleteFile(item.audioPath!));
    }
    if (item.visualPath != null) {
      unawaited(_deleteFile(item.visualPath!));
    }
    notifyListeners();
    _schedulePersist();
    return true;
  }

  Future<void> _deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  void markCollected(
    String id,
    String discId,
    String assetId, {
    String? nfcTagId,
    String? contentId,
    String? nfcUrl,
    String? cloudState,
  }) {
    final now = DateTime.now();
    update(
      id,
      (s) => s.copyWith(
        status: SoundStatus.collected,
        discId: discId,
        assetId: assetId,
        nfcTagId: nfcTagId ?? s.nfcTagId,
        pressedAt: s.pressedAt ?? now,
        contentId: contentId ?? s.contentId,
        nfcUrl: nfcUrl ?? s.nfcUrl,
        cloudState: cloudState ?? s.cloudState ?? 'READY',
      ),
    );
  }

  void markChainFailed(String id, {String? discId, String? nfcTagId}) {
    update(
      id,
      (s) => s.copyWith(
        status: SoundStatus.chainFailed,
        discId: discId ?? s.discId,
        nfcTagId: nfcTagId ?? s.nfcTagId,
      ),
    );
  }

  void markWriteFailed(String id) {
    update(id, (s) => s.copyWith(status: SoundStatus.writeFailed));
  }

  /// 后台管道：开始上传，进入处理中。
  void markUploading(String id) {
    update(id, (s) => s.copyWith(status: SoundStatus.writing));
  }

  /// 后台管道：音频已上传，记录 contentId，仍在处理中（等待云端 READY）。
  void markContentUploaded(String id, String contentId, {String? cloudState}) {
    update(
      id,
      (s) => s.copyWith(
        status: SoundStatus.writing,
        contentId: contentId,
        cloudState: cloudState ?? s.cloudState,
      ),
    );
  }

  /// 后台管道：云端 READY，NFC 可写入，上链可选。
  void markCloudReady(
    String id, {
    required String contentId,
    required String discId,
    String? nfcUrl,
    String? cloudState,
    String? visualPath,
    String? visualUrl,
  }) {
    update(
      id,
      (s) => s.copyWith(
        status: SoundStatus.cloudReady,
        contentId: contentId,
        discId: discId,
        nfcUrl: nfcUrl ?? s.nfcUrl,
        cloudState: cloudState ?? 'READY',
        visualPath: visualPath ?? s.visualPath,
        visualUrl: visualUrl ?? s.visualUrl,
      ),
    );
  }

  /// 后台管道：云端 READY，正在提交上链回执。
  void markChainPending(
    String id, {
    String? contentId,
    String? nfcUrl,
    String? cloudState,
    String? visualPath,
    String? visualUrl,
  }) {
    update(
      id,
      (s) => s.copyWith(
        status: SoundStatus.chainPending,
        contentId: contentId ?? s.contentId,
        nfcUrl: nfcUrl ?? s.nfcUrl,
        cloudState: cloudState ?? s.cloudState ?? 'READY',
        visualPath: visualPath ?? s.visualPath,
        visualUrl: visualUrl ?? s.visualUrl,
      ),
    );
  }

  /// 后台管道：上链完成，待写入 NFC。
  void markChainReady(
    String id, {
    required String contentId,
    required int chainTokenId,
    required String txHash,
    required String contractAddress,
    String? discId,
    String? nfcUrl,
    String? cloudState,
  }) {
    update(
      id,
      (s) => s.copyWith(
        status: SoundStatus.chainReady,
        contentId: contentId,
        discId: discId ?? s.discId,
        assetId: 'token#$chainTokenId',
        tokenId: chainTokenId.toString(),
        txHash: txHash,
        contractLabel: contractAddress,
        networkLabel: 'Injective inEVM Testnet',
        nfcUrl: nfcUrl ?? s.nfcUrl,
        cloudState: cloudState ?? s.cloudState ?? 'READY',
        chainedAt: s.chainedAt ?? DateTime.now(),
      ),
    );
  }

  /// 后台管道：上传/云端处理失败。
  void markUploadFailed(String id) {
    update(id, (s) => s.copyWith(status: SoundStatus.writeFailed));
  }

  /// Merge READY cloud contents into local collection (Drafts stay local-only).
  void syncCloudCollection(List<ContentSummary> remote) {
    for (final item in remote) {
      if (item.state != CloudContentState.ready) continue;
      final existingIndex = _sounds.indexWhere(
        (s) => s.contentId == item.contentId,
      );
      final durationSec = ((item.durationMs ?? 0) / 1000).round().clamp(1, 30);
      final readyAt = DateTime.tryParse(item.readyAt ?? '') ?? DateTime.now();
      final fallbackTitle = item.displayLabel.isNotEmpty
          ? item.displayLabel
          : '云端收藏 · ${formatRecordedAt(readyAt)}';
      if (existingIndex >= 0) {
        final cur = _sounds[existingIndex];
        _sounds[existingIndex] = cur.copyWith(
          status: SoundStatus.collected,
          title: cur.title.isNotEmpty ? cur.title : fallbackTitle,
          nfcUrl: item.nfcUrl ?? cur.nfcUrl,
          visualUrl: item.visualUrl ?? cur.visualUrl,
          cloudState: item.state.wire,
          discId: cur.discId ?? 'CLOUD-${item.contentId.substring(0, 8)}',
        );
      } else {
        _sounds.insert(
          0,
          SoundMemory(
            id: 'cloud_${item.contentId}',
            title: fallbackTitle,
            category: '其他',
            durationSec: durationSec,
            recordedAt: readyAt,
            status: SoundStatus.collected,
            contentId: item.contentId,
            nfcUrl: item.nfcUrl,
            visualUrl: item.visualUrl,
            cloudState: item.state.wire,
            discId: 'CLOUD-${item.contentId.substring(0, 8)}',
            networkLabel: 'Cloud Media',
          ),
        );
      }
    }
    for (final s in _sounds) {
      if (s.visualUrl != null && s.visualPath == null && s.contentId != null) {
        unawaited(VisualShapeService.instance
            .cacheFromUrl(
              contentId: s.contentId!,
              url: s.visualUrl!,
            )
            .then((p) {
          if (p != null) update(s.id, (c) => c.copyWith(visualPath: p));
        }));
      }
    }
    notifyListeners();
    _schedulePersist();
  }
}
