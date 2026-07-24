import 'package:flutter/foundation.dart';
import 'dart:math';

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
    this.assetId,
    this.audioPath,
    this.nfcTagId,
    this.pressedAt,
    this.chainedAt,
    this.networkLabel = 'SoundPola Chain (模拟)',
    this.contractLabel,
    this.tokenId,
    this.txHash,
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
      assetId: '0x11cd…90e',
      visualSeed: 5521,
    ),
  ];

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

  void markCollected(String id, String discId, String assetId, {String? nfcTagId}) {
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
      ),
    );
  }

  void markChainFailed(String id, String discId, {String? nfcTagId}) {
    update(
      id,
      (s) => s.copyWith(
        status: SoundStatus.chainFailed,
        discId: discId,
        nfcTagId: nfcTagId ?? s.nfcTagId,
        pressedAt: s.pressedAt ?? DateTime.now(),
      ),
    );
  }

  void markWriteFailed(String id) {
    update(id, (s) => s.copyWith(status: SoundStatus.writeFailed));
  }
}
