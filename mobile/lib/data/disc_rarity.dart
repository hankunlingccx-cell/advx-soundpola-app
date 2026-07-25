import 'dart:convert';
import 'dart:math';

/// 实体声片出厂稀有度。正式产品由工厂写入 NFC；本版空白卡可按比率随机揭晓。
enum DiscRarity {
  n,
  r,
  sr,
  ssr;

  /// 可选 UR 预留，前期不启用。
  // ur,

  String get code => switch (this) {
        DiscRarity.n => 'N',
        DiscRarity.r => 'R',
        DiscRarity.sr => 'SR',
        DiscRarity.ssr => 'SSR',
      };

  String get label => switch (this) {
        DiscRarity.n => '普通',
        DiscRarity.r => '稀有',
        DiscRarity.sr => '超稀有',
        DiscRarity.ssr => '极稀有',
      };

  String get headline => '$code · $label';

  static DiscRarity? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return switch (raw.trim().toUpperCase()) {
      'N' || 'NORMAL' => DiscRarity.n,
      'R' || 'RARE' => DiscRarity.r,
      'SR' || 'SUPER' || 'SUPER_RARE' => DiscRarity.sr,
      'SSR' || 'ULTRA' || 'ULTRA_RARE' => DiscRarity.ssr,
      _ => null,
    };
  }

  /// 过渡期加权随机比率（工厂预写就绪前）：
  /// N 55% · R 28% · SR 12% · SSR 5%。
  static const rollWeights = <DiscRarity, int>{
    DiscRarity.n: 55,
    DiscRarity.r: 28,
    DiscRarity.sr: 12,
    DiscRarity.ssr: 5,
  };

  static final Random _rng = Random();

  /// 按 [rollWeights] 抽取一档稀有度。
  static DiscRarity rollWeighted([Random? random]) {
    final rng = random ?? _rng;
    final total = rollWeights.values.fold<int>(0, (a, b) => a + b);
    var ticket = rng.nextInt(total);
    for (final entry in rollWeights.entries) {
      ticket -= entry.value;
      if (ticket < 0) return entry.key;
    }
    return DiscRarity.n;
  }
}

/// 出厂声片档案（NFC factory 记录）。
class DiscFactoryProfile {
  const DiscFactoryProfile({
    required this.discId,
    required this.rarity,
    required this.series,
    required this.signature,
    this.bound = false,
    this.demo = false,
  });

  final String discId;
  final DiscRarity rarity;
  final String series;
  final String signature;
  final bool bound;

  /// 过渡态：空白标签上按比率随机揭晓的演示出厂数据（正式工厂预写就绪后关闭）。
  final bool demo;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'discId': discId,
        'rarity': rarity.code,
        'series': series,
        'sig': signature,
        'bound': bound,
        if (demo) 'demo': true,
      };

  static DiscFactoryProfile? fromJson(Map<String, dynamic> json) {
    final discId = json['discId'] as String? ?? json['disc_id'] as String?;
    final rarity = DiscRarity.tryParse(
      json['rarity'] as String? ?? json['tier'] as String?,
    );
    final series = json['series'] as String? ?? json['batch'] as String? ?? '';
    final sig = json['sig'] as String? ?? json['signature'] as String? ?? '';
    if (discId == null || discId.isEmpty || rarity == null || sig.isEmpty) {
      return null;
    }
    return DiscFactoryProfile(
      discId: discId,
      rarity: rarity,
      series: series.isEmpty ? 'Unknown' : series,
      signature: sig,
      bound: json['bound'] == true,
      demo: json['demo'] == true,
    );
  }

  DiscFactoryProfile copyWith({bool? bound}) => DiscFactoryProfile(
        discId: discId,
        rarity: rarity,
        series: series,
        signature: signature,
        bound: bound ?? this.bound,
        demo: demo,
      );

  /// 防伪校验：拒绝普通文本字段伪造。演示签名算法，生产应换正式密钥体系。
  bool get isAuthentic => verifySignature(this);

  static bool verifySignature(DiscFactoryProfile profile) {
    final expected = computeSignature(
      discId: profile.discId,
      rarity: profile.rarity,
      series: profile.series,
      demo: profile.demo,
    );
    return expected == profile.signature;
  }

  static String computeSignature({
    required String discId,
    required DiscRarity rarity,
    required String series,
    bool demo = false,
  }) {
    final material =
        'soundpola|factory|${demo ? 'demo' : 'prod'}|$discId|${rarity.code}|$series';
    // 轻量确定性摘要（非加密学 HMAC）；生产应改为服务端/安全芯片签名。
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(material)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// 同一空白 tag 在绑定前复用首次抽取结果，避免反复扫描稀有度跳动。
  static final Map<String, DiscRarity> _interimRollByTag = {};

  /// 空白卡无工厂 MIME 时：按比率随机揭晓稀有度，并生成演示出厂档案。
  static DiscFactoryProfile demoFromTagId(String tagIdHex) {
    final compact = tagIdHex.replaceAll(':', '').toUpperCase();
    final tail = compact.length >= 4
        ? compact.substring(compact.length - 4)
        : compact.padLeft(4, '0');
    final rarity = _interimRollByTag.putIfAbsent(
      compact,
      DiscRarity.rollWeighted,
    );
    final discId = 'SP-$tail';
    const series = 'Interim-Batch';
    final sig = computeSignature(
      discId: discId,
      rarity: rarity,
      series: series,
      demo: true,
    );
    return DiscFactoryProfile(
      discId: discId,
      rarity: rarity,
      series: series,
      signature: sig,
      bound: false,
      demo: true,
    );
  }

  /// 绑定成功后可清掉 interim 缓存（可选；绑定后应以 NFC／本机记录为准）。
  static void clearInterimRoll(String tagIdHex) {
    _interimRollByTag.remove(tagIdHex.replaceAll(':', '').toUpperCase());
  }
}
