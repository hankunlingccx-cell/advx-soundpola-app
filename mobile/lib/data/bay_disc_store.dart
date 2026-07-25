import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A textured disc retained in the Drafts press-machine frosted bay.
class BayStoredDisc {
  const BayStoredDisc({
    required this.id,
    required this.visualSeed,
    required this.droppedAt,
  });

  final String id;
  final int visualSeed;
  final DateTime droppedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'visualSeed': visualSeed,
        'droppedAtMs': droppedAt.millisecondsSinceEpoch,
      };

  factory BayStoredDisc.fromJson(Map<String, dynamic> json) {
    return BayStoredDisc(
      id: json['id'] as String,
      visualSeed: (json['visualSeed'] as num?)?.toInt() ?? 0,
      droppedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['droppedAtMs'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// Persists discs that dropped into the storage bay after a successful write.
/// Local-only, but **scoped per account** (`userId`) so switching users never
/// shows another account's bay. Each disc remains for [retention] (7 days).
class BayDiscStore {
  BayDiscStore._();
  static final instance = BayDiscStore._();

  static const retention = Duration(days: 7);
  static const maxVisible = 5;

  /// Pre-account-scoping key — removed on first load so it cannot leak.
  static const _legacyPrefsKey = 'drafts_bay_discs_v1';
  static const _prefsKeyPrefix = 'drafts_bay_discs_v2_';

  List<BayStoredDisc> _cache = const [];
  String? _boundUserId;
  bool _loaded = false;

  List<BayStoredDisc> get active => List.unmodifiable(_cache);
  String? get boundUserId => _boundUserId;

  String _keyFor(String userId) => '$_prefsKeyPrefix$userId';

  /// Drop in-memory cache (e.g. on logout). Persisted per-user data is kept.
  void clearSession() {
    _cache = const [];
    _boundUserId = null;
    _loaded = false;
  }

  /// Load bay for [userId]. Null / empty → empty bay (not logged in).
  Future<List<BayStoredDisc>> load({required String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    // Never reassign orphaned global discs to any account.
    if (prefs.containsKey(_legacyPrefsKey)) {
      await prefs.remove(_legacyPrefsKey);
    }

    final uid = (userId == null || userId.isEmpty) ? null : userId;
    if (uid == null) {
      _cache = const [];
      _boundUserId = null;
      _loaded = true;
      return active;
    }

    if (_loaded && _boundUserId == uid) return active;

    final raw = prefs.getString(_keyFor(uid));
    if (raw == null || raw.isEmpty) {
      _cache = const [];
      _boundUserId = uid;
      _loaded = true;
      return active;
    }
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .whereType<Map>()
          .map((e) => BayStoredDisc.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final pruned = _prune(list);
      _cache = pruned;
      _boundUserId = uid;
      _loaded = true;
      if (pruned.length != list.length) {
        await _persist(uid);
      }
      return active;
    } catch (_) {
      _cache = const [];
      _boundUserId = uid;
      _loaded = true;
      return active;
    }
  }

  /// Record a newly dropped disc (after NFC write success). Newest last.
  /// Requires a logged-in [userId]; otherwise no-op.
  Future<List<BayStoredDisc>> addDrop({
    required String? userId,
    required String id,
    required int visualSeed,
    DateTime? at,
  }) async {
    final uid = (userId == null || userId.isEmpty) ? null : userId;
    if (uid == null) {
      _cache = const [];
      _boundUserId = null;
      _loaded = true;
      return active;
    }

    if (!_loaded || _boundUserId != uid) {
      await load(userId: uid);
    }

    final droppedAt = at ?? DateTime.now();
    final next = _prune([
      ..._cache.where((d) => d.id != id),
      BayStoredDisc(id: id, visualSeed: visualSeed, droppedAt: droppedAt),
    ]);
    final capped = next.length > maxVisible
        ? next.sublist(next.length - maxVisible)
        : next;
    _cache = capped;
    _boundUserId = uid;
    await _persist(uid);
    return active;
  }

  Future<List<BayStoredDisc>> pruneExpired({required String? userId}) async {
    await load(userId: userId);
    final uid = _boundUserId;
    if (uid == null) return active;
    final next = _prune(_cache);
    if (next.length != _cache.length) {
      _cache = next;
      await _persist(uid);
    }
    return active;
  }

  List<BayStoredDisc> _prune(List<BayStoredDisc> list) {
    final cutoff = DateTime.now().subtract(retention);
    final kept = list.where((d) => d.droppedAt.isAfter(cutoff)).toList()
      ..sort((a, b) => a.droppedAt.compareTo(b.droppedAt));
    return kept;
  }

  Future<void> _persist(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_cache.map((e) => e.toJson()).toList());
    await prefs.setString(_keyFor(userId), encoded);
  }
}
