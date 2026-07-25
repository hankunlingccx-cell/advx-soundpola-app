import 'dart:io';
import 'dart:typed_data';

/// Streaming mono PCM16 → WAV file writer (header patched on [close]).
class StreamingWavWriter {
  StreamingWavWriter({
    required this.path,
    this.sampleRate = 16000,
    this.numChannels = 1,
  });

  final String path;
  final int sampleRate;
  final int numChannels;

  RandomAccessFile? _raf;
  int _dataBytes = 0;
  bool _opened = false;

  Future<void> open() async {
    final file = File(path);
    if (await file.exists()) await file.delete();
    _raf = await file.open(mode: FileMode.write);
    // Placeholder 44-byte header; patched in close().
    await _raf!.writeFrom(Uint8List(44));
    _opened = true;
    _dataBytes = 0;
  }

  Future<void> addPcm16(Uint8List chunk) async {
    if (!_opened || _raf == null) return;
    await _raf!.writeFrom(chunk);
    _dataBytes += chunk.length;
  }

  Future<String> close() async {
    final raf = _raf;
    if (raf == null) return path;
    final dataSize = _dataBytes;
    final header = _buildHeader(
      sampleRate: sampleRate,
      numChannels: numChannels,
      dataBytes: dataSize,
    );
    await raf.setPosition(0);
    await raf.writeFrom(header);
    await raf.close();
    _raf = null;
    _opened = false;
    return path;
  }

  Future<void> cancel() async {
    try {
      await _raf?.close();
    } catch (_) {}
    _raf = null;
    _opened = false;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static Uint8List _buildHeader({
    required int sampleRate,
    required int numChannels,
    required int dataBytes,
  }) {
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    final fileSizeMinus8 = 36 + dataBytes;
    final bd = ByteData(44);
    void fourCC(int o, String s) {
      for (var i = 0; i < 4; i++) {
        bd.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    fourCC(0, 'RIFF');
    bd.setUint32(4, fileSizeMinus8, Endian.little);
    fourCC(8, 'WAVE');
    fourCC(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little); // PCM fmt chunk size
    bd.setUint16(20, 1, Endian.little); // PCM
    bd.setUint16(22, numChannels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);
    fourCC(36, 'data');
    bd.setUint32(40, dataBytes, Endian.little);
    return bd.buffer.asUint8List();
  }
}
