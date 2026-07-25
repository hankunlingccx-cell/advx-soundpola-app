import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../data/bay_disc_store.dart';
import '../../data/disc_rarity.dart';
import '../../theme/app_colors.dart';
import '../../widgets/disc_texture.dart';

/// Cool-white ABS sound press — semi-skeuomorphic digital device.
enum PressMachineMode {
  idle,
  receiving,
  readyToRelease,
  inserting,
  loaded,
  checking,
  verified,
  preparing,
  readyToWrite,
  writing,
  writeSuccess,
  chaining,
  complete,
  interrupted,
  alreadyBound,
  empty,
}

extension PressMachineModeX on PressMachineMode {
  (String, String) get screenLines => switch (this) {
        PressMachineMode.idle => (
            'READY TO PRESS',
            'SELECT A SOUND CARD',
          ),
        PressMachineMode.receiving => (
            'CARD DETECTED',
            'SLIDE UP TO PRESS',
          ),
        PressMachineMode.readyToRelease => (
            'CARD DETECTED',
            'RELEASE TO INSERT',
          ),
        PressMachineMode.inserting => (
            'INSERTING…',
            'LOCKING CARD',
          ),
        PressMachineMode.loaded => (
            'READY TO PRESS',
            'PREPARE TO SEAL',
          ),
        PressMachineMode.checking => (
            'CHECKING PIECE',
            'HOLD BRIEFLY',
          ),
        PressMachineMode.verified => (
            'PIECE VERIFIED',
            'YOU MAY REMOVE',
          ),
        PressMachineMode.preparing => (
            'PREPARING MEMORY',
            'NFC NOT NEEDED',
          ),
        PressMachineMode.readyToWrite => (
            'READY TO WRITE',
            'HOLD PIECE AGAIN',
          ),
        PressMachineMode.writing => (
            'WRITING…',
            'HOLD STEADY',
          ),
        PressMachineMode.writeSuccess => (
            'PRESSED',
            'YOU MAY REMOVE',
          ),
        PressMachineMode.chaining => (
            'REGISTERING',
            'NO NFC NEEDED',
          ),
        PressMachineMode.complete => (
            'MEMORY PRESSED',
            'ADDED TO COLLECTION',
          ),
        PressMachineMode.interrupted => (
            'PRESS PAUSED',
            'CHECK STATUS',
          ),
        PressMachineMode.alreadyBound => (
            'ALREADY BOUND',
            'USE ANOTHER PIECE',
          ),
        PressMachineMode.empty => (
            'QUEUE EMPTY',
            'RECORD A SOUND',
          ),
      };

  double get slotGlow => switch (this) {
        PressMachineMode.idle || PressMachineMode.empty => 0.18,
        PressMachineMode.receiving => 0.45,
        PressMachineMode.readyToRelease => 0.78,
        PressMachineMode.inserting => 0.9,
        PressMachineMode.loaded => 0.35,
        PressMachineMode.checking => 0.55,
        PressMachineMode.verified => 0.7,
        PressMachineMode.preparing => 0.4,
        PressMachineMode.readyToWrite => 0.72,
        PressMachineMode.writing => 0.85,
        PressMachineMode.writeSuccess => 0.8,
        PressMachineMode.chaining => 0.5,
        PressMachineMode.complete => 0.8,
        PressMachineMode.interrupted || PressMachineMode.alreadyBound => 0.28,
      };
}

/// Cool-white ABS shell + top card slot + frosted storage bay beneath.
class PressMachine extends StatelessWidget {
  const PressMachine({
    super.key,
    required this.mode,
    required this.breath,
    this.slotKey,
    this.loadedTitle,
    this.storedDiscs = const [],
    this.pressProgress = 0,
    this.maxHeight = 196,
  });

  final PressMachineMode mode;
  final Animation<double> breath;
  final GlobalKey? slotKey;
  final String? loadedTitle;
  /// Textured discs retained in the frosted bay (up to 7 days / 5 discs).
  final List<BayStoredDisc> storedDiscs;
  final double pressProgress;
  final double maxHeight;

  static const shell = Color(0xFFF3F5F2);
  static const shellDark = Color(0xFFC9CECB);
  static const shellEdge = Color(0xFFFFFFFF);
  static const glass = Color(0xFF080B0A);

  /// Frosted bay height reserved under the ABS body (layout).
  static const bayHeight = 118.0;
  static const bayOverlap = 12.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: breath,
      builder: (context, _) {
        var (line1, line2) = mode.screenLines;
        if ((mode == PressMachineMode.loaded ||
                mode == PressMachineMode.checking ||
                mode == PressMachineMode.readyToWrite ||
                mode == PressMachineMode.preparing) &&
            loadedTitle != null &&
            loadedTitle!.isNotEmpty) {
          line2 = loadedTitle!.toUpperCase();
        }

        final glow = mode == PressMachineMode.idle
            ? mode.slotGlow * (0.7 + 0.3 * breath.value)
            : mode.slotGlow;
        final failFlash = mode == PressMachineMode.interrupted
            ? (0.35 + 0.25 * breath.value)
            : 0.0;

        return LayoutBuilder(
          builder: (context, constraints) {
            final maxW =
                constraints.maxWidth.isFinite ? constraints.maxWidth : 340.0;
            final maxH = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : maxHeight;
            // Body + frosted bay share the allotted height.
            final totalH = math.min(maxH, maxHeight).clamp(180.0, maxHeight);
            final bodyW = math.min(maxW * 0.9, 312.0);
            // Prefer a taller bay so the disc has room to bounce.
            final bayH = math
                .min(bayHeight, totalH * 0.42)
                .clamp(88.0, bayHeight);
            final bodyH =
                (totalH - bayH + bayOverlap).clamp(110.0, totalH);

            return Center(
              child: SizedBox(
                width: bodyW + 8,
                height: bodyH + bayH - bayOverlap + 6,
                child: Stack(
                  alignment: Alignment.topCenter,
                  clipBehavior: Clip.none,
                  children: [
                    // Contact shadow under frosted bay.
                    Positioned(
                      left: 28,
                      right: 28,
                      bottom: 0,
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.42),
                              blurRadius: 16,
                              offset: const Offset(0, 7),
                              spreadRadius: -2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Frosted storage bay — tucked under the ABS shell.
                    Positioned(
                      top: bodyH - bayOverlap,
                      child: _FrostedStorageBay(
                        width: bodyW * 0.78,
                        height: bayH,
                        breath: breath.value,
                        storedDiscs: storedDiscs,
                      ),
                    ),
                    // ABS body — slot carved into the top face.
                    Container(
                      width: bodyW,
                      height: bodyH,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: const LinearGradient(
                          begin: Alignment(-0.85, -1),
                          end: Alignment(0.7, 1),
                          colors: [
                            shellEdge,
                            shell,
                            shellDark,
                          ],
                          stops: [0.0, 0.42, 1.0],
                        ),
                        border: Border.all(
                          color: const Color(0xFFB8BEBA),
                          width: 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.26),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                          const BoxShadow(
                            color: Color(0x66FFFFFF),
                            blurRadius: 0,
                            offset: Offset(0, -0.8),
                            spreadRadius: -0.6,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
                      child: Column(
                        children: [
                          // Slot at top — card inserts downward from above.
                          _CardSlot(
                            key: slotKey,
                            width: bodyW * 0.58,
                            glow: glow,
                            scanning: mode == PressMachineMode.writing ||
                                mode == PressMachineMode.checking ||
                                mode == PressMachineMode.inserting,
                            breath: breath.value,
                          ),
                          const SizedBox(height: 7),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                gradient: const LinearGradient(
                                  begin: Alignment(-0.6, -0.9),
                                  end: Alignment(0.5, 0.9),
                                  colors: [
                                    Color(0xFFE8EBE8),
                                    Color(0xFFD5DAD6),
                                  ],
                                ),
                                border: Border.all(
                                  color: const Color(0xFFB0B6B2),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF6A7A74)
                                        .withValues(alpha: 0.18),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                    spreadRadius: -0.5,
                                  ),
                                  const BoxShadow(
                                    color: Color(0x55FFFFFF),
                                    blurRadius: 0,
                                    offset: Offset(0, 0.8),
                                    spreadRadius: -2,
                                  ),
                                ],
                              ),
                              padding:
                                  const EdgeInsets.fromLTRB(8, 8, 8, 7),
                              child: Row(
                                children: [
                                  _StatusLamps(
                                    mode: mode,
                                    breath: breath.value,
                                    failFlash: failFlash,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _GlassScreen(
                                      line1: line1,
                                      line2: line2,
                                      fail: mode ==
                                          PressMachineMode.interrupted,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _StatusLamps(
                                    mode: mode,
                                    breath: breath.value,
                                    failFlash: failFlash,
                                    mirror: true,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// One physical disc body inside the frosted bay (center coordinates).
class _BayDiscBody {
  _BayDiscBody({
    required this.id,
    required this.seed,
    required this.rarity,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.angle,
    required this.omega,
    required this.settled,
  });

  final String id;
  final int seed;
  DiscRarity? rarity;
  double x;
  double y;
  double vx;
  double vy;
  double angle;
  double omega;
  bool settled;
}

/// Frosted acrylic bin — discs drop in with gravity, wall/floor bounce,
/// and disc–disc collision (centers must not fully coincide).
class _FrostedStorageBay extends StatefulWidget {
  const _FrostedStorageBay({
    required this.width,
    required this.height,
    required this.breath,
    this.storedDiscs = const [],
  });

  final double width;
  final double height;
  final double breath;
  final List<BayStoredDisc> storedDiscs;

  @override
  State<_FrostedStorageBay> createState() => _FrostedStorageBayState();
}

class _FrostedStorageBayState extends State<_FrostedStorageBay>
    with SingleTickerProviderStateMixin {
  static const _discSize = 46.0;
  static const _gravity = 2200.0;
  static const _wallRest = 0.52;
  static const _discRest = 0.46;
  static const _friction = 0.82;
  static const _settleVy = 28.0;
  static const _pad = 6.0;
  /// Minimum center distance — rims may kiss, never fully stack as one.
  static const _minCenterDist = _discSize * 0.98;

  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;
  final List<_BayDiscBody> _bodies = [];

  double get _r => _discSize / 2;
  double get _floor => widget.height - _pad - _r;
  double get _left => _pad + _r;
  double get _right => widget.width - _pad - _r;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _syncDiscs(widget.storedDiscs, animateNewest: false);
  }

  @override
  void didUpdateWidget(covariant _FrostedStorageBay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.storedDiscs.map((d) => d.id).join('|');
    final newIds = widget.storedDiscs.map((d) => d.id).join('|');
    if (oldIds != newIds) {
      final newestId =
          widget.storedDiscs.isEmpty ? null : widget.storedDiscs.last.id;
      final isNewDrop = newestId != null &&
          !oldWidget.storedDiscs.any((d) => d.id == newestId);
      _syncDiscs(widget.storedDiscs, animateNewest: isNewDrop);
    } else if (oldWidget.width != widget.width ||
        oldWidget.height != widget.height) {
      for (final b in _bodies) {
        _clampBody(b);
      }
      _separateOverlaps(iterations: 6);
      _wakeIfNeeded();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _syncDiscs(List<BayStoredDisc> discs, {required bool animateNewest}) {
    if (discs.isEmpty) {
      _bodies.clear();
      _ticker?.stop();
      _lastElapsed = Duration.zero;
      if (mounted) setState(() {});
      return;
    }

    final keep = <_BayDiscBody>[];
    for (var i = 0; i < discs.length; i++) {
      final d = discs[i];
      _BayDiscBody? existing;
      for (final b in _bodies) {
        if (b.id == d.id) {
          existing = b;
          break;
        }
      }
      if (existing != null) {
        existing.rarity = d.rarity;
        keep.add(existing);
      } else {
        final isNewest = animateNewest && d.id == discs.last.id;
        keep.add(_spawnBody(d, dropFromTop: isNewest, index: keep.length));
      }
    }
    _bodies
      ..clear()
      ..addAll(keep);

    _separateOverlaps(iterations: 8);
    _wakeIfNeeded();
    if (mounted) setState(() {});
  }

  _BayDiscBody _spawnBody(
    BayStoredDisc d, {
    required bool dropFromTop,
    required int index,
  }) {
    final rng = math.Random(d.visualSeed);
    if (dropFromTop) {
      return _BayDiscBody(
        id: d.id,
        seed: d.visualSeed,
        rarity: d.rarity,
        x: widget.width * 0.5 + (rng.nextDouble() - 0.5) * 28,
        y: _r + 2,
        vx: (rng.nextDouble() - 0.5) * 160,
        vy: 40 + rng.nextDouble() * 60,
        angle: (rng.nextDouble() - 0.5) * 0.6,
        omega: (rng.nextDouble() - 0.5) * 6.5,
        settled: false,
      );
    }

    final n = math.max(1, widget.storedDiscs.length);
    final span = math.max(8.0, _right - _left);
    final slot = span / n;
    final x = _left + slot * index + slot * 0.5;
    return _BayDiscBody(
      id: d.id,
      seed: d.visualSeed,
      rarity: d.rarity,
      x: x.clamp(_left, _right),
      y: _floor,
      vx: 0,
      vy: 0,
      angle: (rng.nextDouble() - 0.5) * 0.35,
      omega: 0,
      settled: true,
    );
  }

  bool _anyOverlap() {
    for (var i = 0; i < _bodies.length; i++) {
      for (var j = i + 1; j < _bodies.length; j++) {
        final a = _bodies[i];
        final b = _bodies[j];
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        if (dx * dx + dy * dy < _minCenterDist * _minCenterDist) {
          return true;
        }
      }
    }
    return false;
  }

  void _separateOverlaps({int iterations = 3}) {
    for (var iter = 0; iter < iterations; iter++) {
      for (var i = 0; i < _bodies.length; i++) {
        for (var j = i + 1; j < _bodies.length; j++) {
          _resolvePair(_bodies[i], _bodies[j], applyImpulse: false);
        }
      }
      for (final b in _bodies) {
        _clampBody(b);
      }
    }
  }

  void _resolvePair(
    _BayDiscBody a,
    _BayDiscBody b, {
    required bool applyImpulse,
  }) {
    var dx = b.x - a.x;
    var dy = b.y - a.y;
    var dist = math.sqrt(dx * dx + dy * dy);

    // Fully coincident: deterministic push axis from seeds.
    if (dist < 1e-4) {
      final angle = ((a.seed * 31) ^ (b.seed * 17)) * 0.001;
      dx = math.cos(angle);
      dy = math.sin(angle);
      dist = 1e-4;
    }

    if (dist >= _minCenterDist) return;

    final nx = dx / dist;
    final ny = dy / dist;
    final overlap = _minCenterDist - dist;
    final push = overlap * 0.5 + 0.2;
    a.x -= nx * push;
    a.y -= ny * push;
    b.x += nx * push;
    b.y += ny * push;
    a.settled = false;
    b.settled = false;

    if (!applyImpulse) return;

    final rvx = b.vx - a.vx;
    final rvy = b.vy - a.vy;
    final velN = rvx * nx + rvy * ny;
    if (velN >= 0) return;

    final impulse = -(1 + _discRest) * velN / 2;
    a.vx -= impulse * nx;
    a.vy -= impulse * ny;
    b.vx += impulse * nx;
    b.vy += impulse * ny;
    // Spin from tangential relative motion.
    final tx = -ny;
    final ty = nx;
    final velT = rvx * tx + rvy * ty;
    a.omega -= velT * 0.008;
    b.omega += velT * 0.008;
  }

  void _clampBody(_BayDiscBody b) {
    b.x = b.x.clamp(_left, _right);
    b.y = b.y.clamp(_r + 1, _floor);
  }

  void _wakeIfNeeded() {
    if (_bodies.any((b) => !b.settled) || _anyOverlap()) {
      _lastElapsed = Duration.zero;
      _ticker?.stop();
      _ticker?.start();
    } else {
      _ticker?.stop();
      _lastElapsed = Duration.zero;
    }
  }

  void _onTick(Duration elapsed) {
    if (_bodies.isEmpty) {
      _ticker?.stop();
      return;
    }

    final dtMs = _lastElapsed == Duration.zero
        ? 16.0
        : (elapsed - _lastElapsed).inMicroseconds / 1000.0;
    _lastElapsed = elapsed;
    final dt = (dtMs / 1000.0).clamp(0.0, 0.033);

    for (final b in _bodies) {
      if (b.settled) continue;
      b.vy += _gravity * dt;
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.angle += b.omega * dt;

      if (b.x < _left) {
        b.x = _left;
        b.vx = -b.vx * _wallRest;
        b.omega *= -0.7;
      } else if (b.x > _right) {
        b.x = _right;
        b.vx = -b.vx * _wallRest;
        b.omega *= -0.7;
      }

      if (b.y >= _floor) {
        b.y = _floor;
        if (b.vy > 0) {
          b.vy = -b.vy * _wallRest;
          b.vx *= _friction;
          b.omega *= 0.78;
          b.omega += -b.vx * 0.012;
        }
        if (b.vy.abs() < _settleVy && b.vx.abs() < 18) {
          b.vy = 0;
          b.vx = 0;
          b.omega *= 0.5;
          if (b.omega.abs() < 0.15) {
            b.omega = 0;
            b.settled = true;
          }
        }
      }

      if (b.y < _r + 1) {
        b.y = _r + 1;
        if (b.vy < 0) b.vy = -b.vy * 0.2;
      }
    }

    for (var pass = 0; pass < 3; pass++) {
      for (var i = 0; i < _bodies.length; i++) {
        for (var j = i + 1; j < _bodies.length; j++) {
          _resolvePair(_bodies[i], _bodies[j], applyImpulse: true);
        }
      }
      for (final b in _bodies) {
        _clampBody(b);
      }
    }

    if (_anyOverlap()) {
      for (final b in _bodies) {
        if (b.settled) {
          b.settled = false;
          b.vx += ((b.seed % 5) - 2) * 14.0;
        }
      }
    }

    final allQuiet = _bodies.every((b) => b.settled) && !_anyOverlap();
    if (allQuiet) {
      _ticker?.stop();
      _lastElapsed = Duration.zero;
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final occupied = widget.storedDiscs.isNotEmpty;
    final pulse = 0.55 + 0.45 * widget.breath;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(10),
        bottom: Radius.circular(20),
      ),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(10),
              bottom: Radius.circular(20),
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.14),
                Colors.white.withValues(alpha: 0.06),
                const Color(0xFF1A2220).withValues(alpha: 0.42),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, 0.35),
                      radius: 0.95,
                      colors: [
                        AppColors.accent.withValues(
                          alpha: occupied ? 0.10 * pulse : 0.03,
                        ),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              for (final b in _bodies)
                Positioned(
                  left: b.x - _r,
                  top: b.y - _r,
                  width: _discSize,
                  height: _discSize,
                  child: Transform.rotate(
                    angle: b.angle,
                    child: _BayTexturedDisc(
                      rarity: b.rarity,
                      size: _discSize,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular textured sound disc — same rarity asset as Collection (`discTextureFor`).
class _BayTexturedDisc extends StatelessWidget {
  const _BayTexturedDisc({
    required this.rarity,
    required this.size,
  });

  final DiscRarity? rarity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final texture = discTextureFor(rarity);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              texture,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) => ColoredBox(
                color: switch (rarity) {
                  DiscRarity.r => const Color(0xFF63E0CB),
                  DiscRarity.sr => const Color(0xFF7454EB),
                  DiscRarity.ssr => const Color(0xFFED4F8F),
                  _ => const Color(0xFF212121),
                },
              ),
            ),
            // Light sheen only — do not cover center star / rarity art.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-0.8, -1),
                  end: const Alignment(0.4, 0.35),
                  colors: [
                    Colors.white.withValues(alpha: 0.16),
                    Colors.white.withValues(alpha: 0.04),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.08),
                  ],
                  stops: const [0.0, 0.28, 0.55, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardSlot extends StatelessWidget {
  const _CardSlot({
    super.key,
    required this.width,
    required this.glow,
    required this.scanning,
    required this.breath,
  });

  final double width;
  final double glow;
  final bool scanning;
  final double breath;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: width,
        height: 18,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          // Recessed metal lip molded into ABS.
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFD8DDD9),
              Color(0xFFB4BAB5),
              Color(0xFF8E9691),
            ],
          ),
          border: Border.all(color: const Color(0xFF9AA19C), width: 0.85),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.06 + 0.3 * glow),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(2.5, 3, 2.5, 2.5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF0C100F),
                      Color(0xFF1A201D),
                      Color(0xFF0E1210),
                    ],
                  ),
                  border: Border.all(
                    color: Color.lerp(
                      const Color(0xFF2C3430),
                      AppColors.accent,
                      glow * 0.55,
                    )!,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  height: double.infinity,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1.5),
                    color: AppColors.accent.withValues(
                      alpha: 0.05 + 0.28 * glow,
                    ),
                  ),
                ),
              ),
              if (scanning)
                Align(
                  alignment: Alignment(-1 + breath * 2, 0),
                  child: Container(
                    width: 24,
                    margin: const EdgeInsets.symmetric(vertical: 1.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(1.5),
                      gradient: LinearGradient(
                        colors: [
                          AppColors.accent.withValues(alpha: 0),
                          AppColors.accent.withValues(alpha: 0.55),
                          AppColors.accent.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassScreen extends StatelessWidget {
  const _GlassScreen({
    required this.line1,
    required this.line2,
    this.fail = false,
  });

  final String line1;
  final String line2;
  final bool fail;

  @override
  Widget build(BuildContext context) {
    final accent = fail
        ? const Color(0xFFE07A5F)
        : AppColors.accent;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: PressMachine.glass,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A322F)),
        gradient: const LinearGradient(
          begin: Alignment(-0.8, -1),
          end: Alignment(0.4, 0.6),
          colors: [
            Color(0xFF141918),
            Color(0xFF080B0A),
            Color(0xFF060807),
          ],
          stops: [0.0, 0.35, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
          const BoxShadow(
            color: Color(0x22FFFFFF),
            blurRadius: 0,
            offset: Offset(0, 0.7),
            spreadRadius: -1.5,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            line1,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.15,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            line2,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 8.5,
              color: accent.withValues(alpha: 0.92),
              height: 1.2,
              letterSpacing: 0.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLamps extends StatelessWidget {
  const _StatusLamps({
    required this.mode,
    required this.breath,
    this.failFlash = 0,
    this.mirror = false,
  });

  final PressMachineMode mode;
  final double breath;
  final double failFlash;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    final lit = switch (mode) {
      PressMachineMode.idle || PressMachineMode.empty => 1,
      PressMachineMode.receiving || PressMachineMode.readyToRelease => 2,
      PressMachineMode.inserting => 2,
      PressMachineMode.loaded ||
      PressMachineMode.checking ||
      PressMachineMode.verified ||
      PressMachineMode.preparing ||
      PressMachineMode.readyToWrite =>
        2,
      PressMachineMode.writing ||
      PressMachineMode.writeSuccess ||
      PressMachineMode.chaining ||
      PressMachineMode.complete =>
        3,
      PressMachineMode.interrupted || PressMachineMode.alreadyBound => 2,
    };

    final chase = mode == PressMachineMode.writing ||
            mode == PressMachineMode.checking
        ? ((breath * 3).floor() % 3)
        : -1;
    final allPulse = mode == PressMachineMode.complete;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final idx = mirror ? 2 - i : i;
        var on = idx < lit;
        var pulse = 1.0;
        if (mode == PressMachineMode.idle && idx == 0) {
          pulse = 0.55 + 0.45 * breath;
        } else if (chase >= 0) {
          on = idx <= chase;
          pulse = idx == chase ? 1.0 : 0.55;
        } else if (allPulse) {
          pulse = 0.75 + 0.25 * breath;
        } else if (failFlash > 0 && on) {
          pulse = failFlash;
        } else if (on && idx == lit - 1) {
          pulse = 0.7 + 0.3 * breath;
        }

        final color = failFlash > 0 && on
            ? Color.lerp(
                const Color(0xFFD0D4D1),
                const Color(0xFFE07A5F),
                failFlash,
              )!
            : (on
                ? AppColors.accent.withValues(alpha: 0.9 * pulse)
                : const Color(0xFFD0D4D1));

        return Padding(
          padding: EdgeInsets.only(bottom: i < 2 ? 5 : 0),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: const Color(0xFFA8AFA8),
                width: 0.65,
              ),
              boxShadow: on && failFlash == 0
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.28 * pulse),
                        blurRadius: 3,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      }),
    );
  }
}
