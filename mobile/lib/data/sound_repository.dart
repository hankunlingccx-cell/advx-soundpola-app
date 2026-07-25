import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../cloud/cloud_media_models.dart';
import '../services/visual_shape_service.dart';
import '../visual/audio_feature_timeline.dart';
import 'disc_rarity.dart';

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

/// Drafts 空列表原因：初始 / 全部封存 / 全部删除。
enum DraftsEmptyKind { firstUse, allPressed, cleared }

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
    this.discRarity,
    this.discSeries,
    this.assetId,
    this.audioPath,
    this.nfcTagId,
    this.pressedAt,
    this.chainedAt,
    this.networkLabel = 'SoundPola Chain (模拟)',
    this.contractLabel,
    this.tokenId,
    this.txHash,
    this.contentId,
    this.nfcUrl,
    this.cloudState,
    this.visualUrl,
    this.visualPath,
    this.packageDir,
    this.coverPath,
    this.visualMjpgPath,
    this.visualIdxPath,
    this.visualManifestPath,
    this.audioFeaturesPath,
    this.visualBakeStatus = VisualBakeStatus.none,
    this.visualBakeError,
    this.rendererVersion = kSoundVisualRendererVersion,
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
  /// 由实体声片出厂决定；Draft 阶段为 null（待揭晓）。
  final DiscRarity? discRarity;
  final String? discSeries;
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
  /// Local cached path of the visual JSON.
  final String? visualPath;

  /// Package root: sounds/{id}/
  final String? packageDir;
  final String? coverPath;
  final String? visualMjpgPath;
  final String? visualIdxPath;
  final String? visualManifestPath;
  final String? audioFeaturesPath;
  final VisualBakeStatus visualBakeStatus;
  final String? visualBakeError;
  final String rendererVersion;

  bool get hasIndexedVisual =>
      visualBakeStatus == VisualBakeStatus.ready &&
      visualMjpgPath != null &&
      visualIdxPath != null;

  /// Draft / 未绑定时展示「待揭晓」。
  bool get rarityPending => discRarity == null;

  String get rarityDisplayLabel =>
      discRarity?.headline ?? '待揭晓';

  SoundMemory copyWith({
    String? title,
    String? category,
    String? description,
    SoundStatus? status,
    String? discId,
    DiscRarity? discRarity,
    String? discSeries,
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
    String? packageDir,
    String? coverPath,
    String? visualMjpgPath,
    String? visualIdxPath,
    String? visualManifestPath,
    String? audioFeaturesPath,
    VisualBakeStatus? visualBakeStatus,
    String? visualBakeError,
    bool clearVisualBakeError = false,
    String? rendererVersion,
    int? visualSeed,
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
      visualSeed: visualSeed ?? this.visualSeed,
      discId: discId ?? this.discId,
      discRarity: discRarity ?? this.discRarity,
      discSeries: discSeries ?? this.discSeries,
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
      packageDir: packageDir ?? this.packageDir,
      coverPath: coverPath ?? this.coverPath,
      visualMjpgPath: visualMjpgPath ?? this.visualMjpgPath,
      visualIdxPath: visualIdxPath ?? this.visualIdxPath,
      visualManifestPath: visualManifestPath ?? this.visualManifestPath,
      audioFeaturesPath: audioFeaturesPath ?? this.audioFeaturesPath,
      visualBakeStatus: visualBakeStatus ?? this.visualBakeStatus,
      visualBakeError: clearVisualBakeError
          ? null
          : (visualBakeError ?? this.visualBakeError),
      rendererVersion: rendererVersion ?? this.rendererVersion,
    );
  }
}

/// 分类名称最长字数（用户自建）。
const int kCategoryNameMaxLength = 12;

/// Collection 按分类聚合的一组收藏（瀑布流胶囊单元）。
class CollectionGroup {
  const CollectionGroup({
    required this.category,
    required this.items,
  });

  final String category;
  final List<SoundMemory> items;

  int get count => items.length;
}

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
  SoundRepository._() {
    _seedCategoriesFromSounds();
    _loadPersistedCategories();
  }
  static final SoundRepository instance = SoundRepository._();

  /// Kept for App boot compatibility (l branch persistence path).
  Future<void> init() async {}

  static const _prefsCategoriesKey = 'user_categories';

  /// 本会话内草稿清空原因（用于「清空 / 全部封存」文案；展示一次后消费）。
  DraftsEmptyKind? draftsEmptyKind;
  bool _everHadDrafts = false;

  /// 用户已创建／已使用的分类名（顺序：声音出现顺序，再追加持久化自建名）。
  final List<String> _categories = [];

  bool get everHadDrafts => _everHadDrafts;
  bool get hasCollectionAssets => collection.isNotEmpty;
  int get draftCount => drafts.length;

  /// 可供选择的分类列表（用户自定义）。
  List<String> get categories => List.unmodifiable(_categories);

  final List<SoundMemory> _sounds = [];

  List<SoundMemory> get sounds => List.unmodifiable(_sounds);

  List<SoundMemory> get drafts =>
      _sounds.where((s) => s.status != SoundStatus.collected).toList();

  List<SoundMemory> get collection =>
      _sounds.where((s) => s.status == SoundStatus.collected).toList();

  /// 按分类分组；顺序跟随 [categories]，未知分类靠后。
  List<CollectionGroup> get collectionGroups {
    final items = collection;
    final byCategory = <String, List<SoundMemory>>{};
    for (final item in items) {
      byCategory.putIfAbsent(item.category, () => []).add(item);
    }
    for (final list in byCategory.values) {
      list.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    }

    final groups = <CollectionGroup>[];
    for (final name in _categories) {
      final list = byCategory.remove(name);
      if (list != null && list.isNotEmpty) {
        groups.add(CollectionGroup(category: name, items: list));
      }
    }
    for (final entry in byCategory.entries) {
      if (entry.value.isNotEmpty) {
        groups.add(CollectionGroup(category: entry.key, items: entry.value));
      }
    }
    return groups;
  }

  void _seedCategoriesFromSounds() {
    final seen = <String>{};
    for (final s in _sounds) {
      final name = s.category.trim();
      if (name.isEmpty || !seen.add(name)) continue;
      _categories.add(name);
    }
  }

  Future<void> _loadPersistedCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsCategoriesKey) ?? const [];
    var changed = false;
    for (final raw in stored) {
      final name = raw.trim();
      if (name.isEmpty || _categories.contains(name)) continue;
      _categories.add(name);
      changed = true;
    }
    await _persistCategories();
    if (changed) notifyListeners();
  }

  Future<void> _persistCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsCategoriesKey, _categories);
  }

  /// 规范化并加入分类表；已存在则原样返回。失败返回 null。
  Future<String?> addCategory(String raw) async {
    final name = raw.trim();
    if (name.isEmpty || name.length > kCategoryNameMaxLength) return null;
    if (_categories.contains(name)) return name;
    _categories.add(name);
    await _persistCategories();
    notifyListeners();
    return name;
  }

  void _ensureCategoryPresent(String raw) {
    final name = raw.trim();
    if (name.isEmpty || _categories.contains(name)) return;
    if (name.length > kCategoryNameMaxLength) return;
    _categories.add(name);
    _persistCategories();
  }

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

  SoundMemory? findByDiscId(String discId) {
    try {
      return _sounds.firstWhere((s) => s.discId == discId);
    } catch (_) {
      return null;
    }
  }

  void addDraft(SoundMemory memory) {
    draftsEmptyKind = null;
    _everHadDrafts = true;
    _ensureCategoryPresent(memory.category);
    _sounds.insert(0, memory.copyWith(status: SoundStatus.drafted));
    notifyListeners();
  }

  void update(String id, SoundMemory Function(SoundMemory) transform) {
    final index = _sounds.indexWhere((s) => s.id == id);
    if (index >= 0) {
      _sounds[index] = transform(_sounds[index]);
      _ensureCategoryPresent(_sounds[index].category);
      notifyListeners();
    }
  }

  /// 调整收藏展示分类（不改变链上资产）。
  void updateCategory(String id, String category) {
    final name = category.trim();
    if (name.isEmpty || !_categories.contains(name)) return;
    update(id, (s) {
      if (s.category == name) return s;
      return s.copyWith(category: name);
    });
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
    final wasDraft = item.status != SoundStatus.collected;
    _sounds.removeAt(index);
    if (item.packageDir != null) {
      unawaited(_deleteDir(item.packageDir!));
    } else {
      if (item.audioPath != null) {
        unawaited(_deleteFile(item.audioPath!));
      }
      if (item.visualPath != null) {
        unawaited(_deleteFile(item.visualPath!));
      }
      if (item.coverPath != null) {
        unawaited(_deleteFile(item.coverPath!));
      }
    }
    if (wasDraft && drafts.isEmpty) {
      draftsEmptyKind = DraftsEmptyKind.cleared;
    }
    notifyListeners();
    return true;
  }

  Future<void> _deleteDir(String path) async {
    try {
      final d = Directory(path);
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> _deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// 消费一次性空态提示（清空 / 全部封存），之后恢复为常规空态。
  void consumeDraftsEmptyKind() {
    if (draftsEmptyKind == null) return;
    draftsEmptyKind = null;
    notifyListeners();
  }

  void markCollected(
    String id,
    String discId,
    String assetId, {
    String? nfcTagId,
    String? contentId,
    String? nfcUrl,
    String? cloudState,
    DiscRarity? discRarity,
    String? discSeries,
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
        chainedAt: now,
        contractLabel: s.contractLabel ?? '0xSoundPola…mock',
        tokenId: s.tokenId ?? id.substring(0, id.length.clamp(0, 8)),
        txHash: s.txHash ?? assetId,
        contentId: contentId ?? s.contentId,
        nfcUrl: nfcUrl ?? s.nfcUrl,
        cloudState: cloudState ?? s.cloudState ?? 'READY',
        discRarity: discRarity ?? s.discRarity,
        discSeries: discSeries ?? s.discSeries,
      ),
    );
    if (drafts.isEmpty) {
      draftsEmptyKind = DraftsEmptyKind.allPressed;
    }
  }

  void markChainFailed(
    String id,
    String discId, {
    String? nfcTagId,
    DiscRarity? discRarity,
    String? discSeries,
  }) {
    update(
      id,
      (s) => s.copyWith(
        status: SoundStatus.chainFailed,
        discId: discId,
        nfcTagId: nfcTagId ?? s.nfcTagId,
        pressedAt: s.pressedAt ?? DateTime.now(),
        discRarity: discRarity ?? s.discRarity,
        discSeries: discSeries ?? s.discSeries,
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
      if (existingIndex >= 0) {
        final cur = _sounds[existingIndex];
        _sounds[existingIndex] = cur.copyWith(
          status: SoundStatus.collected,
          title: cur.title.isNotEmpty ? cur.title : item.displayLabel,
          nfcUrl: item.nfcUrl ?? cur.nfcUrl,
          cloudState: item.state.wire,
          assetId: cur.assetId ?? item.contentId,
          discId: cur.discId ?? 'CLOUD-${item.contentId.substring(0, 8)}',
          chainedAt: cur.chainedAt ?? DateTime.now(),
        );
      } else {
        _sounds.insert(
          0,
          SoundMemory(
            id: 'cloud_${item.contentId}',
            title: item.displayLabel.isNotEmpty
                ? item.displayLabel
                : '云端声音 ${item.contentId.substring(0, 8)}',
            category: '其他',
            durationSec: durationSec,
            status: SoundStatus.collected,
            contentId: item.contentId,
            nfcUrl: item.nfcUrl,
            cloudState: item.state.wire,
            assetId: item.contentId,
            discId: 'CLOUD-${item.contentId.substring(0, 8)}',
            chainedAt: DateTime.tryParse(item.readyAt ?? '') ?? DateTime.now(),
            networkLabel: 'Cloud Media',
          ),
        );
        _ensureCategoryPresent('其他');
      }
    }
    for (final s in List<SoundMemory>.from(_sounds)) {
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
  }
}
