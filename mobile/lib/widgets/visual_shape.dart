import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Cloud-produced 3D visual shape: 3 bundles × 24 polar control points.
///
/// Schema: `polar-points-v1`. Each point is `(r, th)` in unit space:
/// - `r` ∈ [0.08, 1.05] (radius, matches `_spineAt` clamp range)
/// - `th` ∈ [0.04, 0.96] (normalized half-sector angular position, matches
///   `_spineAt` output)
///
/// Mirrors the local `_CtrlBuffer` contract in `sound_visual.dart`
/// (`_bundleCount`=3 × `_controlPoints`=24 = 72 points total). The cloud
/// provides the static skeleton; the local layer applies 6-fold rotation,
/// time "breath", color gradient, and AudioFeatures micro-modulation on top.
class SoundVisualShape {
  const SoundVisualShape({required this.bundles});

  /// `[3][24]` polar points `(r, th)`.
  final List<List<Offset>> bundles;

  static const _schema = 'polar-points-v1';
  static const _bundleCount = 3; // mirrors sound_visual.dart _bundleCount
  static const _controlPoints = 24; // mirrors sound_visual.dart _controlPoints

  factory SoundVisualShape.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != _schema) {
      throw const FormatException(
          'visual schema mismatch (expected polar-points-v1)');
    }
    final raw = json['bundles'];
    if (raw is! List || raw.length != _bundleCount) {
      throw const FormatException('visual bundles: expected 3 bundles');
    }
    final out = raw.map((bundle) {
      if (bundle is! List || bundle.length != _controlPoints) {
        throw const FormatException('visual bundle: expected 24 points');
      }
      return bundle.map((p) {
        final m = p as Map;
        final r = (m['r'] as num?)?.toDouble();
        final th = (m['th'] as num?)?.toDouble();
        if (r == null || th == null) {
          throw const FormatException('visual point: missing r/th');
        }
        return Offset(r, th);
      }).toList();
    }).toList();
    return SoundVisualShape(bundles: out);
  }

  /// Synchronous file read + parse. Returns null on any failure so callers
  /// fall back to seed-based rendering.
  static SoundVisualShape? fromFile(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      final decoded = jsonDecode(f.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return null;
      return SoundVisualShape.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}
