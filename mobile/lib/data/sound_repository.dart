import 'package:flutter/foundation.dart';
import 'dart:math';
import '../cloud/cloud_media_models.dart';
import 'disc_rarity.dart';

enum SoundStatus {
  drafted,
  writing,
  writeFailed,
  chainPending,
  chainFailed,
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
  SoundRepository._();
  static final SoundRepository instance = SoundRepository._();

  final List<SoundMemory> _sounds = [
    SoundMemory(
      title: '雨落窗台',
      category: '自然',
      description: '午后忽然下起小雨。',
      durationSec: 28,
      locationLabel: '杭州 · 西湖',
      visualSeed: 1201,
    ),
    SoundMemory(
      title: '地铁报站',
      category: '城市',
      durationSec: 12,
      locationLabel: '上海',
      status: SoundStatus.writeFailed,
      visualSeed: 3340,
    ),
    SoundMemory(
      title: '凌晨的风',
      category: '自然',
      description: 'NFC 已写入，等待上链',
      durationSec: 18,
      locationLabel: '大理',
      status: SoundStatus.chainFailed,
      discId: 'SP-2026-0312-C2',
      discRarity: DiscRarity.sr,
      discSeries: 'Genesis-01',
      visualSeed: 4412,
    ),
    SoundMemory(
      title: '散场前的合唱',
      category: '特别时刻',
      description: '没有拍舞台，只留下身边一起唱的声音。',
      durationSec: 46,
      locationLabel: '首尔 · 汉江',
      status: SoundStatus.collected,
      discId: 'SP-2026-0718-A3',
      discRarity: DiscRarity.ssr,
      discSeries: 'Genesis-01',
      assetId: '0x8f2a…c91',
      visualSeed: 7788,
    ),
    SoundMemory(
      title: '妈妈说早点回来',
      category: '人声',
      description: '电话里很短的一句。',
      durationSec: 9,
      status: SoundStatus.collected,
      discId: 'SP-2026-0702-B1',
      discRarity: DiscRarity.r,
      discSeries: 'Genesis-01',
      assetId: '0x11cd…90e',
      visualSeed: 5521,
    ),
    SoundMemory(
      title: '夜市炒板栗',
      category: '城市',
      durationSec: 22,
      locationLabel: '成都 · 宽窄巷',
      status: SoundStatus.collected,
      discId: 'SP-2026-0611-D4',
      discRarity: DiscRarity.n,
      discSeries: 'Everyday-02',
      assetId: '0x3ab1…e02',
      visualSeed: 2109,
    ),
    SoundMemory(
      title: '路口红绿灯',
      category: '城市',
      durationSec: 15,
      locationLabel: '东京',
      status: SoundStatus.collected,
      discId: 'SP-2026-0520-E1',
      discRarity: DiscRarity.sr,
      discSeries: 'City-03',
      assetId: '0x77c0…a14',
      visualSeed: 8831,
    ),
    SoundMemory(
      title: '海浪拍岸',
      category: '自然',
      durationSec: 40,
      locationLabel: '厦门 · 环岛路',
      status: SoundStatus.collected,
      discId: 'SP-2026-0418-N2',
      discRarity: DiscRarity.r,
      discSeries: 'Nature-01',
      assetId: '0x90fe…b33',
      visualSeed: 3012,
    ),
    SoundMemory(
      title: '山间蝉鸣',
      category: '自然',
      durationSec: 33,
      locationLabel: '莫干山',
      status: SoundStatus.collected,
      discId: 'SP-2026-0801-N7',
      discRarity: DiscRarity.ssr,
      discSeries: 'Nature-01',
      assetId: '0x12aa…d80',
      visualSeed: 6644,
    ),
    SoundMemory(
      title: '开箱胶带声',
      category: '日常',
      durationSec: 8,
      locationLabel: '家中',
      status: SoundStatus.collected,
      discId: 'SP-2026-0303-F2',
      discRarity: DiscRarity.n,
      discSeries: 'Everyday-02',
      assetId: '0x55d1…c07',
      visualSeed: 1455,
    ),
    SoundMemory(
      title: '煮咖啡的咕嘟',
      category: '日常',
      durationSec: 19,
      locationLabel: '家中厨房',
      status: SoundStatus.collected,
      discId: 'SP-2026-0228-F5',
      discRarity: DiscRarity.n,
      discSeries: 'Everyday-02',
      assetId: '0xabe2…119',
      visualSeed: 9201,
    ),
    SoundMemory(
      title: '火车过隧道',
      category: '旅行',
      durationSec: 27,
      locationLabel: '瑞士',
      status: SoundStatus.collected,
      discId: 'SP-2026-0912-T1',
      discRarity: DiscRarity.sr,
      discSeries: 'Travel-04',
      assetId: '0x44f9…882',
      visualSeed: 4770,
    ),
    SoundMemory(
      title: '机场登机广播',
      category: '旅行',
      durationSec: 14,
      locationLabel: '浦东 T2',
      status: SoundStatus.collected,
      discId: 'SP-2026-0915-T3',
      discRarity: DiscRarity.r,
      discSeries: 'Travel-04',
      assetId: '0x6c01…fe4',
      visualSeed: 5882,
    ),
    SoundMemory(
      title: '旅店窗外雨',
      category: '旅行',
      durationSec: 36,
      locationLabel: '京都',
      status: SoundStatus.collected,
      discId: 'SP-2026-1002-T8',
      discRarity: DiscRarity.ssr,
      discSeries: 'Travel-04',
      assetId: '0xd3a0…651',
      visualSeed: 2399,
    ),
    SoundMemory(
      title: '朋友的笑声',
      category: '人声',
      durationSec: 11,
      locationLabel: '上海 · 咖啡馆',
      status: SoundStatus.collected,
      discId: 'SP-2026-0709-B3',
      discRarity: DiscRarity.r,
      discSeries: 'Genesis-01',
      assetId: '0x81bc…330',
      visualSeed: 7110,
    ),
  ];

  List<SoundMemory> get sounds => List.unmodifiable(_sounds);

  List<SoundMemory> get drafts =>
      _sounds.where((s) => s.status != SoundStatus.collected).toList();

  List<SoundMemory> get collection =>
      _sounds.where((s) => s.status == SoundStatus.collected).toList();

  /// 按分类分组；顺序跟随 [soundCategories]，未知分类靠后。
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
    for (final name in soundCategories) {
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

  SoundMemory? get(String id) {
    try {
      return _sounds.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  void addDraft(SoundMemory memory) {
    _sounds.insert(0, memory.copyWith(status: SoundStatus.drafted));
    notifyListeners();
  }

  void update(String id, SoundMemory Function(SoundMemory) transform) {
    final index = _sounds.indexWhere((s) => s.id == id);
    if (index >= 0) {
      _sounds[index] = transform(_sounds[index]);
      notifyListeners();
    }
  }

  /// 调整收藏展示分类（不改变链上资产）。
  void updateCategory(String id, String category) {
    if (!soundCategories.contains(category)) return;
    update(id, (s) {
      if (s.category == category) return s;
      return s.copyWith(category: category);
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
    _sounds.removeAt(index);
    notifyListeners();
    return true;
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
      }
    }
    notifyListeners();
  }
}
