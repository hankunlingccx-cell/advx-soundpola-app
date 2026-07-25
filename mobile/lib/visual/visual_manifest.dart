import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'audio_feature_timeline.dart';

class VisualFrameIndexEntry {
  const VisualFrameIndexEntry({
    required this.frame,
    required this.timeMs,
    required this.offset,
    required this.length,
    this.width = kVisualBakeSize,
    this.height = kVisualBakeSize,
  });

  final int frame;
  final int timeMs;
  final int offset;
  final int length;
  final int width;
  final int height;

  Map<String, Object> toJson() => {
        'frame': frame,
        'timeMs': timeMs,
        'offset': offset,
        'length': length,
        'width': width,
        'height': height,
      };

  factory VisualFrameIndexEntry.fromJson(Map<String, dynamic> m) =>
      VisualFrameIndexEntry(
        frame: (m['frame'] as num).toInt(),
        timeMs: (m['timeMs'] as num).toInt(),
        offset: (m['offset'] as num).toInt(),
        length: (m['length'] as num).toInt(),
        width: (m['width'] as num?)?.toInt() ?? kVisualBakeSize,
        height: (m['height'] as num?)?.toInt() ?? kVisualBakeSize,
      );
}

class VisualManifest {
  const VisualManifest({
    required this.width,
    required this.height,
    required this.fps,
    required this.frameCount,
    required this.durationMs,
    required this.jpegQuality,
    required this.audioId,
    required this.visualSeed,
    required this.rendererVersion,
    this.format = 'indexed-mjpeg',
    this.version = 1,
    this.coverFrame = 0,
  });

  final String format;
  final int version;
  final int width;
  final int height;
  final double fps;
  final int frameCount;
  final int durationMs;
  final int jpegQuality;
  final String audioId;
  final int visualSeed;
  final String rendererVersion;
  final int coverFrame;

  Map<String, Object> toJson() => {
        'format': format,
        'version': version,
        'width': width,
        'height': height,
        'fps': fps,
        'frameCount': frameCount,
        'durationMs': durationMs,
        'jpegQuality': jpegQuality,
        'audioId': audioId,
        'visualSeed': visualSeed,
        'rendererVersion': rendererVersion,
        'coverFrame': coverFrame,
      };

  factory VisualManifest.fromJson(Map<String, dynamic> m) => VisualManifest(
        format: m['format'] as String? ?? 'indexed-mjpeg',
        version: (m['version'] as num?)?.toInt() ?? 1,
        width: (m['width'] as num).toInt(),
        height: (m['height'] as num).toInt(),
        fps: (m['fps'] as num).toDouble(),
        frameCount: (m['frameCount'] as num).toInt(),
        durationMs: (m['durationMs'] as num).toInt(),
        jpegQuality: (m['jpegQuality'] as num?)?.toInt() ?? kVisualBakeJpegQuality,
        audioId: m['audioId'] as String? ?? '',
        visualSeed: (m['visualSeed'] as num?)?.toInt() ?? 0,
        rendererVersion:
            m['rendererVersion'] as String? ?? kSoundVisualRendererVersion,
        coverFrame: (m['coverFrame'] as num?)?.toInt() ?? 0,
      );

  static Future<VisualManifest?> load(File file) async {
    if (!await file.exists()) return null;
    final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return VisualManifest.fromJson(map);
  }

  Future<void> save(File file) async {
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
  }
}

class VisualFrameIndex {
  VisualFrameIndex(this.entries);

  final List<VisualFrameIndexEntry> entries;

  int get length => entries.length;

  VisualFrameIndexEntry? entryForTimeMs(int timeMs) {
    if (entries.isEmpty) return null;
    if (timeMs <= entries.first.timeMs) return entries.first;
    if (timeMs >= entries.last.timeMs) return entries.last;
    var lo = 0;
    var hi = entries.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (entries[mid].timeMs <= timeMs) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    // Nearest
    final a = entries[lo];
    final b = entries[hi];
    return (timeMs - a.timeMs).abs() <= (b.timeMs - timeMs).abs() ? a : b;
  }

  VisualFrameIndexEntry? entryForFrame(int frame) {
    if (frame < 0 || frame >= entries.length) return null;
    return entries[frame];
  }

  Future<void> save(File file) async {
    final list = entries.map((e) => e.toJson()).toList();
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(list));
  }

  static Future<VisualFrameIndex> load(File file) async {
    final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
    return VisualFrameIndex(
      raw
          .map((e) => VisualFrameIndexEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Random-access JPEG reader over concatenated MJPEG.
class IndexedMjpegReader {
  IndexedMjpegReader({
    required this.mjpgFile,
    required this.index,
  });

  final File mjpgFile;
  final VisualFrameIndex index;
  RandomAccessFile? _raf;

  Future<void> open() async {
    _raf = await mjpgFile.open();
  }

  Future<void> close() async {
    await _raf?.close();
    _raf = null;
  }

  Future<Uint8List?> readFrameAtTimeMs(int timeMs) async {
    final entry = index.entryForTimeMs(timeMs);
    if (entry == null) return null;
    return readEntry(entry);
  }

  Future<Uint8List?> readEntry(VisualFrameIndexEntry entry) async {
    final raf = _raf;
    if (raf == null) return null;
    await raf.setPosition(entry.offset);
    return raf.read(entry.length);
  }
}
