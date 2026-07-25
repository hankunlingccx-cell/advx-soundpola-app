import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/sound_repository.dart';
import '../visual/audio_feature_timeline.dart';
import '../visual/visual_manifest.dart';
import 'sound_visual.dart';

/// Plays indexed MJPEG frames locked to [positionMsListenable] (audio clock).
class IndexedVisualPlayer extends StatefulWidget {
  const IndexedVisualPlayer({
    super.key,
    required this.item,
    required this.positionMsListenable,
    this.fit = BoxFit.contain,
    this.showProgressRing = false,
    this.progress = 0,
    this.fallbackSeed,
  });

  final SoundMemory item;
  final ValueListenable<int> positionMsListenable;
  final BoxFit fit;
  final bool showProgressRing;
  final double progress;
  /// Used when bake not ready — live canvas fallback.
  final int? fallbackSeed;

  @override
  State<IndexedVisualPlayer> createState() => _IndexedVisualPlayerState();
}

class _IndexedVisualPlayerState extends State<IndexedVisualPlayer> {
  IndexedMjpegReader? _reader;
  VisualFrameIndex? _index;
  ui.Image? _image;
  int _lastFrame = -1;
  bool _ready = false;
  bool _failed = false;

  bool get _hasPackage =>
      widget.item.visualBakeStatus == VisualBakeStatus.ready &&
      widget.item.visualMjpgPath != null &&
      widget.item.visualIdxPath != null;

  @override
  void initState() {
    super.initState();
    widget.positionMsListenable.addListener(_onPosition);
    _open();
  }

  @override
  void didUpdateWidget(covariant IndexedVisualPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionMsListenable != widget.positionMsListenable) {
      oldWidget.positionMsListenable.removeListener(_onPosition);
      widget.positionMsListenable.addListener(_onPosition);
    }
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.visualMjpgPath != widget.item.visualMjpgPath) {
      _close();
      _open();
    }
  }

  @override
  void dispose() {
    widget.positionMsListenable.removeListener(_onPosition);
    _close();
    super.dispose();
  }

  Future<void> _open() async {
    _failed = false;
    _ready = false;
    if (!_hasPackage) {
      if (mounted) setState(() {});
      return;
    }
    try {
      final idx = await VisualFrameIndex.load(File(widget.item.visualIdxPath!));
      final reader = IndexedMjpegReader(
        mjpgFile: File(widget.item.visualMjpgPath!),
        index: idx,
      );
      await reader.open();
      _index = idx;
      _reader = reader;
      _ready = true;
      await _showFrame(widget.positionMsListenable.value);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('IndexedVisualPlayer open failed: $e');
      _failed = true;
      if (mounted) setState(() {});
    }
  }

  Future<void> _close() async {
    await _reader?.close();
    _reader = null;
    _index = null;
    _image?.dispose();
    _image = null;
    _lastFrame = -1;
  }

  void _onPosition() {
    _showFrame(widget.positionMsListenable.value);
  }

  Future<void> _showFrame(int timeMs) async {
    final reader = _reader;
    final index = _index;
    if (reader == null || index == null) return;
    final entry = index.entryForTimeMs(timeMs);
    if (entry == null || entry.frame == _lastFrame) return;
    _lastFrame = entry.frame;
    final bytes = await reader.readEntry(entry);
    if (bytes == null || !mounted) return;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final prev = _image;
    _image = frame.image;
    prev?.dispose();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPackage || _failed || !_ready || _image == null) {
      // Fallback: live deterministic canvas (no stored frames yet).
      return SoundVisualCanvas(
        seed: widget.fallbackSeed ?? widget.item.visualSeed,
        mode: SoundVisualMode.complete,
        showProgressRing: widget.showProgressRing,
        progress: widget.progress,
      );
    }
    return CustomPaint(
      painter: _FramePainter(
        image: _image!,
        fit: widget.fit,
        showProgressRing: widget.showProgressRing,
        progress: widget.progress,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({
    required this.image,
    required this.fit,
    required this.showProgressRing,
    required this.progress,
  });

  final ui.Image image;
  final BoxFit fit;
  final bool showProgressRing;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dest = _applyBoxFit(fit, src.size, size);
    canvas.drawImageRect(image, src, dest, Paint());
    if (showProgressRing) {
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
  }

  Rect _applyBoxFit(BoxFit fit, Size input, Size output) {
    final fitted = applyBoxFit(fit, input, output);
    final dx = (output.width - fitted.destination.width) / 2;
    final dy = (output.height - fitted.destination.height) / 2;
    return Rect.fromLTWH(
      dx,
      dy,
      fitted.destination.width,
      fitted.destination.height,
    );
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) =>
      old.image != image ||
      old.progress != progress ||
      old.showProgressRing != showProgressRing;
}
