import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../audio/audio_features.dart';

/// Dev-only HUD for AGC / soft-gate / band calibration. Toggle with [visible].
class AudioDriveDebugPanel extends StatefulWidget {
  const AudioDriveDebugPanel({
    super.key,
    required this.features,
    this.visible = true,
  });

  final ValueListenable<AudioFeatures>? features;
  final bool visible;

  @override
  State<AudioDriveDebugPanel> createState() => _AudioDriveDebugPanelState();
}

class _AudioDriveDebugPanelState extends State<AudioDriveDebugPanel> {
  double _fps = 0;
  Duration? _last;
  int _frames = 0;
  double _fpsAcc = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback(_tickFps);
  }

  void _tickFps(Duration now) {
    if (!mounted) return;
    if (_last != null) {
      final dt = (now - _last!).inMicroseconds / 1e6;
      if (dt > 0 && dt < 0.5) {
        _frames++;
        _fpsAcc += 1.0 / dt;
        if (_frames >= 15) {
          _fps = _fpsAcc / _frames;
          _frames = 0;
          _fpsAcc = 0;
          if (widget.visible) setState(() {});
        }
      }
    }
    _last = now;
    SchedulerBinding.instance.addPostFrameCallback(_tickFps);
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode || !widget.visible || widget.features == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<AudioFeatures>(
      valueListenable: widget.features!,
      builder: (context, f, _) {
        String n(double v, [int d = 2]) => v.toStringAsFixed(d);
        final lines = [
          'raw ${n(f.rms)}  gated ${n(f.gatedRms)}',
          'floor ${n(f.noiseFloor, 3)}  peak ${n(f.trackedPeak)}',
          'AGC× ${n(f.agcGain, 1)}',
          'fast ${n(f.fastEnvelope)}  slow ${n(f.slowEnvelope)}',
          'B ${n(f.bass)} LM ${n(f.lowMid)} M ${n(f.mid)}',
          'HM ${n(f.highMid)} T ${n(f.treble)}',
          'cent ${n(f.spectralCentroid)} flux ${n(f.spectralFlux)}',
          'onset ${n(f.onset)} zcr ${n(f.zeroCrossingRate)}',
          'FPS ${_fps.toStringAsFixed(0)}',
        ];
        return Align(
          alignment: Alignment.topLeft,
          child: IgnorePointer(
            child: Container(
              margin: const EdgeInsets.only(top: 4, left: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xCC0A1210),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x3363E0CB)),
              ),
              child: DefaultTextStyle(
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 10,
                  height: 1.25,
                  color: Color(0xCC63E0CB),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: lines.map((e) => Text(e)).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
