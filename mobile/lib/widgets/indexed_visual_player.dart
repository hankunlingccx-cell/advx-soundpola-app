import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/sound_repository.dart';
import '../visual/audio_feature_timeline.dart';
import '../visual/visual_manifest.dart';
import 'sound_visual.dart';

/// Plays indexed MJPEG frames locked to [positionMsListenable] (audio clock).
///
/// Decode path: only the latest target frame is applied; stale async results
/// are discarded. A small LRU of decoded [ui.Image]s avoids re-decoding
/// nearby seeks / loops.
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
  /// Used when bake not ready — live canvas / cover fallback.
  final int? fallbackSeed;

  @override
  State<IndexedVisualPlayer> createState() => _IndexedVisualPlayerState();
}

class _IndexedVisualPlayerState extends State<IndexedVisualPlayer> {
  static const _lruCapacity = 8;

  IndexedMjpegReader? _reader;
  VisualFrameIndex? _index;
  ui.Image? _image;
  int _lastFrame = -1;
  int _requestGen = 0;
  int? _inflightFrame;
  bool _ready = false;
  bool _failed = false;

  /// frameIndex → decoded image (owned by this state until evicted/disposed).
  final LinkedHashMap<int, ui.Image> _lru = LinkedHashMap();

  bool get _hasPackage =>
      widget.item.visualBakeStatus == VisualBakeStatus.ready &&
      widget.item.visualMjpgPath != null &&
      widget.item.visualIdxPath != null;

  String? get _coverPath {
    final p = widget.item.coverPath;
    if (p == null || p.isEmpty) return null;
    return p;
  }

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
    _requestGen++;
    await _reader?.close();
    _reader = null;
    _index = null;
    _clearLru(keepDisplay: false);
    _image = null;
    _lastFrame = -1;
    _inflightFrame = null;
  }

  void _clearLru({required bool keepDisplay}) {
    for (final img in _lru.values) {
      if (keepDisplay && identical(img, _image)) continue;
      img.dispose();
    }
    _lru.clear();
    if (keepDisplay && _image != null) {
      // Display image is no longer tracked — dispose on next replace.
    }
  }

  void _touchLru(int frame, ui.Image image) {
    _lru.remove(frame);
    _lru[frame] = image;
    while (_lru.length > _lruCapacity) {
      final firstKey = _lru.keys.first;
      final evicted = _lru.remove(firstKey);
      if (evicted != null && !identical(evicted, _image)) {
        evicted.dispose();
      }
    }
  }

  void _onPosition() {
    _showFrame(widget.positionMsListenable.value);
  }

  Future<void> _showFrame(int timeMs) async {
    final reader = _reader;
    final index = _index;
    if (reader == null || index == null) return;
    final entry = index.entryForTimeMs(timeMs);
    if (entry == null) return;
    if (entry.frame == _lastFrame && _image != null) return;

    // Prefer cache — no disk / decode.
    final cached = _lru.remove(entry.frame);
    if (cached != null) {
      _lru[entry.frame] = cached; // move to MRU
      _lastFrame = entry.frame;
      _image = cached;
      if (mounted) setState(() {});
      _prefetch(entry.frame + 1);
      return;
    }

    // Coalesce: if same frame already decoding, skip; always track latest gen.
    if (_inflightFrame == entry.frame) return;
    final gen = ++_requestGen;
    _inflightFrame = entry.frame;
    final targetFrame = entry.frame;

    final bytes = await reader.readEntry(entry);
    if (!mounted || gen != _requestGen) {
      if (_inflightFrame == targetFrame) _inflightFrame = null;
      return;
    }
    if (bytes == null) {
      _inflightFrame = null;
      return;
    }

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted || gen != _requestGen) {
      frame.image.dispose();
      if (_inflightFrame == targetFrame) _inflightFrame = null;
      return;
    }

    _lastFrame = targetFrame;
    _image = frame.image;
    _touchLru(targetFrame, frame.image);
    _inflightFrame = null;
    if (mounted) setState(() {});
    _prefetch(targetFrame + 1);
  }

  /// Warm next frame into LRU without switching display.
  Future<void> _prefetch(int frameIndex) async {
    final reader = _reader;
    final index = _index;
    if (reader == null || index == null) return;
    if (_lru.containsKey(frameIndex)) return;
    if (frameIndex < 0 || frameIndex >= index.entries.length) return;
    final entry = index.entries[frameIndex];
    final gen = _requestGen;
    final bytes = await reader.readEntry(entry);
    if (!mounted || gen != _requestGen || bytes == null) return;
    if (_lru.containsKey(frameIndex)) return;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted || gen != _requestGen) {
        frame.image.dispose();
        return;
      }
      _touchLru(frameIndex, frame.image);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_hasPackage && !_failed && _ready && _image != null) {
      return RepaintBoundary(
        child: CustomPaint(
          painter: _FramePainter(
            image: _image!,
            fit: widget.fit,
            showProgressRing: widget.showProgressRing,
            progress: widget.progress,
          ),
          child: const SizedBox.expand(),
        ),
      );
    }

    // Prefer static cover over live complete canvas (no ticker).
    final cover = _coverPath;
    if (cover != null && File(cover).existsSync()) {
      return RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(cover),
              fit: widget.fit,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => _fallbackCanvas(),
            ),
            if (widget.showProgressRing)
              CustomPaint(
                painter: _ProgressRingPainter(progress: widget.progress),
              ),
          ],
        ),
      );
    }

    return _fallbackCanvas();
  }

  Widget _fallbackCanvas() {
    return SoundVisualCanvas(
      seed: widget.fallbackSeed ?? widget.item.visualSeed,
      mode: SoundVisualMode.complete,
      showProgressRing: widget.showProgressRing,
      progress: widget.progress,
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
      _paintRing(canvas, size, progress);
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
      !identical(old.image, image) ||
      old.fit != fit ||
      old.showProgressRing != showProgressRing ||
      old.progress != progress;
}

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) => _paintRing(canvas, size, progress);

  @override
  bool shouldRepaint(covariant _ProgressRingPainter old) =>
      old.progress != progress;
}

void _paintRing(Canvas canvas, Size size, double progress) {
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
