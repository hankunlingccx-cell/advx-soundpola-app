import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/sound_repository.dart';
import 'indexed_visual_player.dart';
import 'sound_visual.dart';

/// Cover + playback from the same bake package.
///
/// Idle → [SoundMemory.coverPath] (representative frame from Indexed-MJPEG).
/// Playing / scrubbing → [IndexedVisualPlayer] locked to [positionMsListenable].
/// Fallback → live [SoundVisualCanvas] only when bake/cover are missing.
class BakedSoundVisual extends StatelessWidget {
  const BakedSoundVisual({
    super.key,
    required this.item,
    required this.positionMsListenable,
    this.playing = false,
    this.fit = BoxFit.cover,
    this.showProgressRing = false,
    this.progress = 0,
    this.fallbackSeed,
  });

  final SoundMemory item;
  final ValueListenable<int> positionMsListenable;
  final bool playing;
  final BoxFit fit;
  final bool showProgressRing;
  final double progress;
  final int? fallbackSeed;

  bool get _coverOk {
    final p = item.coverPath;
    return p != null && p.isNotEmpty && File(p).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    // Time-locked bake frames while playing / with progress ring.
    if (item.hasIndexedVisual && (playing || showProgressRing)) {
      return IndexedVisualPlayer(
        item: item,
        positionMsListenable: positionMsListenable,
        fit: fit,
        showProgressRing: showProgressRing,
        progress: progress,
        fallbackSeed: fallbackSeed ?? item.visualSeed,
      );
    }

    // Idle: representative cover from the same bake stream.
    if (_coverOk && !playing) {
      return _CoverFace(
        path: item.coverPath!,
        fit: fit,
        showProgressRing: showProgressRing,
        progress: progress,
        fallbackSeed: fallbackSeed ?? item.visualSeed,
      );
    }

    if (item.hasIndexedVisual) {
      return IndexedVisualPlayer(
        item: item,
        positionMsListenable: positionMsListenable,
        fit: fit,
        showProgressRing: showProgressRing,
        progress: progress,
        fallbackSeed: fallbackSeed ?? item.visualSeed,
      );
    }

    // No bake yet — live canvas while playing; cover if somehow present.
    if (!playing && _coverOk) {
      return _CoverFace(
        path: item.coverPath!,
        fit: fit,
        showProgressRing: showProgressRing,
        progress: progress,
        fallbackSeed: fallbackSeed ?? item.visualSeed,
      );
    }

    return SoundVisualCanvas(
      seed: fallbackSeed ?? item.visualSeed,
      mode: playing ? SoundVisualMode.playback : SoundVisualMode.complete,
      active: playing,
      showProgressRing: showProgressRing,
      progress: progress,
    );
  }
}

class _CoverFace extends StatelessWidget {
  const _CoverFace({
    required this.path,
    required this.fit,
    required this.showProgressRing,
    required this.progress,
    required this.fallbackSeed,
  });

  final String path;
  final BoxFit fit;
  final bool showProgressRing;
  final double progress;
  final int fallbackSeed;

  @override
  Widget build(BuildContext context) {
    final image = Image.file(
      File(path),
      fit: fit,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => SoundVisualCanvas(
        seed: fallbackSeed,
        mode: SoundVisualMode.complete,
        showProgressRing: showProgressRing,
        progress: progress,
      ),
    );
    if (!showProgressRing) return image;
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        CustomPaint(painter: _CoverRingPainter(progress: progress)),
      ],
    );
  }
}

class _CoverRingPainter extends CustomPainter {
  _CoverRingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: side * 0.46),
      -3.14159265 / 2,
      3.14159265 * 2 * progress.clamp(0, 1),
      false,
      Paint()
        ..color = const Color(0xFF63E0CB).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CoverRingPainter old) =>
      old.progress != progress;
}
