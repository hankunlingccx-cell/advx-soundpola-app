import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 空状态变体：初始 / 清空 / 条件筛选 / 阻断 / 处理中 / 错误。
enum EmptyStateVariant {
  firstUse,
  cleared,
  filtered,
  blocked,
  processing,
  error,
}

/// 统一五层空状态面板（状态码 + 空设备视觉 + 中英标题说明 + 主/次操作）。
class EmptyStatePanel extends StatefulWidget {
  const EmptyStatePanel({
    super.key,
    required this.statusCode,
    required this.title,
    required this.description,
    required this.visual,
    this.variant = EmptyStateVariant.firstUse,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.compact = false,
  });

  final String statusCode;
  final String title;
  final String description;
  final Widget visual;
  final EmptyStateVariant variant;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool compact;

  @override
  State<EmptyStatePanel> createState() => _EmptyStatePanelState();
}

class _EmptyStatePanelState extends State<EmptyStatePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      _breath.stop();
      _breath.value = 0.35;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: widget.compact ? AppSpacing.item : AppSpacing.section,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _breath,
            builder: (context, child) {
              final t = reduce ? 0.35 : _breath.value;
              final float = reduce ? 0.0 : (t - 0.5) * 2.4;
              return Transform.translate(
                offset: Offset(0, float),
                child: Opacity(
                  opacity: 0.38 + t * 0.12,
                  child: child,
                ),
              );
            },
            child: SizedBox(
              width: math.min(MediaQuery.sizeOf(context).width * 0.56, 220),
              child: widget.visual,
            ),
          ),
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: _breath,
            builder: (context, _) {
              final t = reduce ? 0.5 : _breath.value;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withValues(
                        alpha: 0.25 + t * 0.45,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.statusCode,
                    style: TextStyle(
                      color: AppColors.textTertiary.withValues(alpha: 0.9),
                      fontSize: 11,
                      letterSpacing: 1.4,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFF2F5F4),
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF727A78),
              fontSize: 14,
              height: 1.55,
            ),
          ),
          if (widget.primaryLabel != null && widget.onPrimary != null) ...[
            const SizedBox(height: 28),
            SizedBox(
              width: 200,
              height: 48,
              child: FilledButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  widget.onPrimary!();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.accentOn,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.button),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  widget.primaryLabel!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
          if (widget.secondaryLabel != null && widget.onSecondary != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: widget.onSecondary,
              child: Text(
                widget.secondaryLabel!,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 空设备色板（规范：#080C0B / #151B19 / #252D2B）。
abstract final class EmptyDeviceColors {
  static const deep = Color(0xFF080C0B);
  static const mid = Color(0xFF151B19);
  static const edge = Color(0xFF252D2B);
  static const line = Color(0xFF3A4441);
}

/// Collection 空轨道线框视觉。
class EmptyTrackVisual extends StatelessWidget {
  const EmptyTrackVisual({super.key, this.pendingSlots = 0});

  /// >0 时显示若干未激活定位点（有草稿待封存）。
  final int pendingSlots;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.72,
      child: CustomPaint(
        painter: _EmptyTrackPainter(pendingSlots: pendingSlots.clamp(0, 5)),
      ),
    );
  }
}

class _EmptyTrackPainter extends CustomPainter {
  _EmptyTrackPainter({required this.pendingSlots});
  final int pendingSlots;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = EmptyDeviceColors.edge.withValues(alpha: 0.85);

    final fill = Paint()..color = EmptyDeviceColors.deep;

    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.18, 4, size.width * 0.64, size.height - 8),
      const Radius.circular(40),
    );
    canvas.drawRRect(r, fill);
    canvas.drawRRect(r, stroke);

    // 稀疏空定位点
    final cx = size.width / 2;
    final slots = pendingSlots > 0 ? pendingSlots : 3;
    for (var i = 0; i < slots; i++) {
      final cy = size.height * (0.22 + i * 0.22);
      final radius = size.width * 0.16;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = EmptyDeviceColors.line.withValues(
          alpha: pendingSlots > 0 ? 0.55 : 0.35,
        );
      canvas.drawCircle(Offset(cx, cy), radius, p);
      if (pendingSlots > 0) {
        // 未激活半透明位，不显示稀有度
        canvas.drawCircle(
          Offset(cx, cy),
          radius * 0.85,
          Paint()..color = EmptyDeviceColors.mid.withValues(alpha: 0.45),
        );
      }
    }

    // 扫描光点
    final scanY = size.height * 0.12;
    canvas.drawCircle(
      Offset(cx, scanY),
      2.2,
      Paint()..color = AppColors.accent.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _EmptyTrackPainter oldDelegate) =>
      oldDelegate.pendingSlots != pendingSlots;
}

/// Drafts 空托盘：断开四角定位线（非骨架屏）。
class EmptyTrayVisual extends StatelessWidget {
  const EmptyTrayVisual({super.key, this.complete = false});

  final bool complete;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.15,
      child: CustomPaint(painter: _EmptyTrayPainter(complete: complete)),
    );
  }
}

class _EmptyTrayPainter extends CustomPainter {
  _EmptyTrayPainter({required this.complete});
  final bool complete;

  @override
  void paint(Canvas canvas, Size size) {
    // 上方机器轮廓（低亮度）
    final machine = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.2, 0, size.width * 0.6, size.height * 0.38),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      machine,
      Paint()..color = EmptyDeviceColors.mid.withValues(alpha: 0.9),
    );
    canvas.drawRRect(
      machine,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = EmptyDeviceColors.edge,
    );

    // 插槽关闭线
    final slotY = size.height * 0.32;
    canvas.drawLine(
      Offset(size.width * 0.32, slotY),
      Offset(size.width * 0.68, slotY),
      Paint()
        ..color = EmptyDeviceColors.line
        ..strokeWidth = 2,
    );

    // 机器小屏文案区
    final screen = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.34,
        size.height * 0.08,
        size.width * 0.32,
        size.height * 0.16,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(screen, Paint()..color = EmptyDeviceColors.deep);
    final tp = TextPainter(
      text: TextSpan(
        text: complete ? 'QUEUE COMPLETE' : 'QUEUE EMPTY',
        style: TextStyle(
          color: AppColors.accent.withValues(alpha: 0.45),
          fontSize: 7,
          fontFamily: 'monospace',
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.3);
    tp.paint(
      canvas,
      Offset(size.width * 0.36, size.height * 0.12),
    );

    // 三组断开四角定位（空托盘）
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = EmptyDeviceColors.line.withValues(alpha: 0.7);
    for (var i = 0; i < 3; i++) {
      final left = size.width * (0.08 + i * 0.32);
      final top = size.height * 0.52;
      final w = size.width * 0.26;
      final h = size.height * 0.38;
      _drawCornerMarks(canvas, Rect.fromLTWH(left, top, w, h), paint);
    }
  }

  void _drawCornerMarks(Canvas canvas, Rect r, Paint paint) {
    const len = 8.0;
    // 四角断开标记
    canvas.drawLine(r.topLeft, r.topLeft + const Offset(len, 0), paint);
    canvas.drawLine(r.topLeft, r.topLeft + const Offset(0, len), paint);
    canvas.drawLine(r.topRight, r.topRight + const Offset(-len, 0), paint);
    canvas.drawLine(r.topRight, r.topRight + const Offset(0, len), paint);
    canvas.drawLine(r.bottomLeft, r.bottomLeft + const Offset(len, 0), paint);
    canvas.drawLine(r.bottomLeft, r.bottomLeft + const Offset(0, -len), paint);
    canvas.drawLine(r.bottomRight, r.bottomRight + const Offset(-len, 0), paint);
    canvas.drawLine(r.bottomRight, r.bottomRight + const Offset(0, -len), paint);
  }

  @override
  bool shouldRepaint(covariant _EmptyTrayPainter oldDelegate) =>
      oldDelegate.complete != complete;
}

/// 录音页：关闭的麦克风端口（权限阻断）。
class EmptyMicPortVisual extends StatelessWidget {
  const EmptyMicPortVisual({super.key, this.locked = true});

  final bool locked;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(painter: _MicPortPainter(locked: locked)),
    );
  }
}

class _MicPortPainter extends CustomPainter {
  _MicPortPainter({required this.locked});
  final bool locked;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    // 低亮度节点线
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = EmptyDeviceColors.line.withValues(alpha: 0.5);
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      canvas.drawLine(
        c,
        c + Offset(math.cos(a), math.sin(a)) * size.width * 0.38,
        line,
      );
    }
    canvas.drawCircle(c, size.width * 0.22, line);

    // 麦克风端口
    final port = Paint()..color = EmptyDeviceColors.mid;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: size.width * 0.28, height: size.height * 0.4),
        const Radius.circular(14),
      ),
      port,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: size.width * 0.28, height: size.height * 0.4),
        const Radius.circular(14),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = EmptyDeviceColors.edge
        ..strokeWidth = 1.2,
    );
    // 关闭闸门
    if (locked) {
      canvas.drawLine(
        Offset(c.dx - size.width * 0.08, c.dy),
        Offset(c.dx + size.width * 0.08, c.dy),
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.35)
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MicPortPainter oldDelegate) =>
      oldDelegate.locked != locked;
}
