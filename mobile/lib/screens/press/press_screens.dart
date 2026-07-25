import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../cloud/cloud_media_client.dart';
import '../../cloud/cloud_media_models.dart';
import '../../cloud/cloud_upload.dart';
import '../../data/disc_rarity.dart';
import '../../data/session.dart';
import '../../data/sound_repository.dart';
import '../../router/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/chain_service.dart';
import '../../services/nfc_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/empty_state_panel.dart';
import '../../widgets/rarity_holo.dart';
import '../../widgets/sound_nft_card.dart';
import '../../widgets/sound_visual.dart';
import '../../widgets/ssr_aura_layer.dart';

class PressMethodScreen extends StatefulWidget {
  const PressMethodScreen({
    super.key,
    required this.id,
    required this.onBack,
    required this.onNfc,
    this.chainOnly = false,
  });

  final String id;
  final VoidCallback onBack;
  final VoidCallback onNfc;
  final bool chainOnly;

  @override
  State<PressMethodScreen> createState() => _PressMethodScreenState();
}

class _PressMethodScreenState extends State<PressMethodScreen> {
  NfcDeviceStatus? _nfcStatus;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    PressSession.clear();
    if (widget.chainOnly) {
      _loading = false;
      return;
    }
    _loadNfc();
  }

  Future<void> _loadNfc() async {
    final status = await NfcService.instance.checkStatus();
    if (mounted) {
      setState(() {
        _nfcStatus = status;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = SoundRepository.instance.get(widget.id);
    if (item == null) {
      return Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: SafeArea(
          child: EmptyStatePanel(
            statusCode: 'NO SOUND TO PRESS',
            title: '没有可写入的声音',
            description: '先录制一段声音，再将它封存到实体声片中。',
            visual: const EmptyTrayVisual(),
            variant: EmptyStateVariant.firstUse,
            primaryLabel: '开始录音',
            onPrimary: widget.onBack,
          ),
        ),
      );
    }

    if (widget.chainOnly) {
      return _buildScaffold(
        item: item,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('上链重试', style: TextStyle(color: AppColors.ink400, fontSize: 13)),
            const SizedBox(height: AppSpacing.item),
            const Text(
              '声片已写入，仅需重新提交上链，不会再次写入 NFC。',
              style: TextStyle(color: AppColors.ink600, height: 1.5),
            ),
            const Spacer(),
            PrimaryButton(text: '重试上链', onPressed: widget.onNfc),
          ],
        ),
      );
    }

    final statusText = switch (_nfcStatus) {
      NfcDeviceStatus.available => 'NFC 已就绪',
      NfcDeviceStatus.disabled => 'NFC 未开启',
      NfcDeviceStatus.unavailable => '本机不支持 NFC',
      null => '检测中…',
    };

    return _buildScaffold(
      item: item,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('准备', style: TextStyle(color: AppColors.ink400, fontSize: 13)),
          const SizedBox(height: AppSpacing.item),
          Text(statusText, style: TextStyle(
            color: _nfcStatus == NfcDeviceStatus.available ? AppColors.primary700 : AppColors.warning,
            fontWeight: FontWeight.w500,
          )),
          const SizedBox(height: AppSpacing.section),
          const Text(
            '选择写入方式，将声音永久绑定到 NFC 声片并创建数字资产。',
            style: TextStyle(color: AppColors.ink600, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.section),
          _MethodCard(
            title: '手机 NFC 写入',
            subtitle: _nfcStatus == NfcDeviceStatus.disabled
                ? '请先开启 NFC'
                : '将手机贴近空白声片完成写入',
            enabled: !_loading && _nfcStatus == NfcDeviceStatus.available,
            onTap: widget.onNfc,
          ),
          if (_nfcStatus == NfcDeviceStatus.disabled) ...[
            const SizedBox(height: AppSpacing.tight),
            SecondaryButton(
              text: '前往开启 NFC',
              onPressed: NfcService.instance.openNfcSettings,
            ),
          ],
          const SizedBox(height: AppSpacing.tight),
          _MethodCard(
            title: '硬件设备写入',
            subtitle: '发送写入任务至已连接设备，在设备端完成写入',
            enabled: !_loading,
            onTap: () => context.push(AppRoutes.pressHardwarePath(widget.id)),
          ),
        ],
      ),
    );
  }

  Widget _buildScaffold({required SoundMemory? item, required Widget body}) {
    return Scaffold(
      backgroundColor: AppColors.canvasBg,
      appBar: AppBar(
        backgroundColor: AppColors.canvasBg,
        elevation: 0,
        foregroundColor: AppColors.ink600,
        title: const Text('Press', style: TextStyle(color: AppColors.ink950)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item != null) ...[
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.chip),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: ColoredBox(
                          color: AppColors.primary50,
                          child: SoundVisualCanvas(seed: item.visualSeed, active: false),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.tight),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            '${item.category} · ${formatDuration(item.durationSec)}',
                            style: const TextStyle(color: AppColors.ink600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.section),
              ],
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.item),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.line200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: AppColors.ink600, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _DetectState { searching, bound, ready, unreadable, error }

class PressDetectScreen extends StatefulWidget {
  const PressDetectScreen({
    super.key,
    required this.id,
    required this.onBack,
    required this.onDetected,
  });

  final String id;
  final VoidCallback onBack;
  final VoidCallback onDetected;

  @override
  State<PressDetectScreen> createState() => _PressDetectScreenState();
}

class _PressDetectScreenState extends State<PressDetectScreen> {
  _DetectState _state = _DetectState.searching;
  String _message = '正在检测 NFC…';
  String? _boundDiscId;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _startDetect();
  }

  @override
  void dispose() {
    NfcService.instance.stopSession();
    super.dispose();
  }

  Future<void> _startDetect() async {
    final status = await NfcService.instance.checkStatus();
    if (status != NfcDeviceStatus.available) {
      setState(() {
        _state = _DetectState.error;
        _message = status == NfcDeviceStatus.disabled ? 'NFC 未开启' : '本机不支持 NFC';
      });
      return;
    }

    try {
      await NfcService.instance.startSession(
        alertMessage: '将手机背面靠近声片',
        onDiscovered: (tag) async {
          if (_handled) return;
          try {
            final binding = await NfcService.instance.readBinding(tag);
            if (binding != null) {
              _handled = true;
              await NfcService.instance.stopSession();
              if (mounted) {
                setState(() {
                  _state = _DetectState.bound;
                  _boundDiscId = binding.discId;
                  _message = binding.rarity != null
                      ? '该声片已绑定（${binding.rarity!.code}），无法覆盖'
                      : '该声片已绑定，无法覆盖';
                });
              }
              return;
            }
            final tagId = NfcService.instance.tagIdHex(tag);
            if (!await NfcService.instance.canWriteTag(tag)) {
              if (mounted) {
                setState(() {
                  _state = _DetectState.unreadable;
                  _message = '未识别到可写入的空白声片';
                });
              }
              return;
            }
            final factory = await NfcService.instance.readFactoryProfile(tag);
            if (factory == null) {
              if (mounted) {
                setState(() {
                  _state = _DetectState.unreadable;
                  _message = '未识别到正版声片出厂信息';
                });
              }
              return;
            }
            if (factory.bound) {
              _handled = true;
              await NfcService.instance.stopSession();
              if (mounted) {
                setState(() {
                  _state = _DetectState.bound;
                  _boundDiscId = factory.discId;
                  _message = '该声片已绑定，无法覆盖';
                });
              }
              return;
            }
            _handled = true;
            PressSession.set(
              tagId: tagId,
              disc: factory.discId,
              discRarity: factory.rarity,
              discSeries: factory.series,
              signature: factory.signature,
              demo: factory.demo,
            );
            await NfcService.instance.stopSession(message: '声片已识别');
            if (mounted) {
              setState(() {
                _state = _DetectState.ready;
                _message = '声片 ${factory.discId} · 稀有度待揭晓';
              });
              widget.onDetected();
            }
          } catch (e) {
            if (mounted) {
              setState(() {
                _state = _DetectState.error;
                _message = e.toString();
              });
            }
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _DetectState.error;
          _message = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvasBg,
      appBar: AppBar(
        backgroundColor: AppColors.canvasBg,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        title: const Text('检测声片'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              NfcRippleVisual(active: _state == _DetectState.searching),
              const SizedBox(height: AppSpacing.section),
              const Text('将手机背面靠近声片', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Text(_message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.ink600)),
              if (_boundDiscId != null)
                Text('已绑定：$_boundDiscId', style: const TextStyle(color: AppColors.error, fontSize: 13)),
              if (_state == _DetectState.error || _state == _DetectState.unreadable) ...[
                const SizedBox(height: AppSpacing.section),
                PrimaryButton(text: '重新检测', onPressed: () {
                  setState(() {
                    _state = _DetectState.searching;
                    _message = '正在检测 NFC…';
                    _handled = false;
                  });
                  _startDetect();
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PressConfirmScreen extends StatefulWidget {
  const PressConfirmScreen({
    super.key,
    required this.id,
    required this.onBack,
    required this.onConfirm,
  });

  final String id;
  final VoidCallback onBack;
  final VoidCallback onConfirm;

  @override
  State<PressConfirmScreen> createState() => _PressConfirmScreenState();
}

class _PressConfirmScreenState extends State<PressConfirmScreen> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final item = SoundRepository.instance.get(widget.id);
    final discId = PressSession.discId ?? item?.discId ?? '—';
    final rarity = PressSession.rarity ?? item?.discRarity;
    return Scaffold(
      backgroundColor: AppColors.canvasBg,
      appBar: AppBar(
        backgroundColor: AppColors.canvasBg,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        title: const Text('永久绑定确认'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item != null)
                SizedBox(
                  height: 160,
                  child: SoundVisualCanvas(seed: item.visualSeed, active: false),
                ),
              const SizedBox(height: AppSpacing.item),
              if (item != null) ...[
                Text(item.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                Text('#${item.category}', style: const TextStyle(color: AppColors.ink600)),
              ],
              const SizedBox(height: AppSpacing.item),
              MetaRow(label: '声片编号', value: discId),
              MetaRow(
                label: '稀有度',
                value: rarity?.headline ?? '待揭晓',
              ),
              if (PressSession.series != null)
                MetaRow(label: '系列', value: PressSession.series!),
              MetaRow(label: '写入方式', value: '手机 NFC'),
              const SizedBox(height: AppSpacing.item),
              Container(
                padding: const EdgeInsets.all(AppSpacing.tight),
                decoration: BoxDecoration(
                  color: AppColors.primary50,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: const Text(
                  '每张声片只能写入一个声音。写入完成后，声音和声片将永久绑定，无法替换或覆盖。稀有度由实体声片决定，不可编辑。',
                  style: TextStyle(color: AppColors.ink800, height: 1.5, fontSize: 14),
                ),
              ),
              const SizedBox(height: AppSpacing.item),
              InkWell(
                onTap: () => setState(() => _checked = !_checked),
                child: Row(
                  children: [
                    Checkbox(value: _checked, onChanged: (v) => setState(() => _checked = v ?? false)),
                    const Expanded(child: Text('我已确认当前声音和声片')),
                  ],
                ),
              ),
              const Spacer(),
              PrimaryButton(
                text: '确认并永久绑定',
                enabled: _checked,
                onPressed: _checked ? widget.onConfirm : null,
              ),
              const SizedBox(height: AppSpacing.tight),
              SecondaryButton(text: '返回检查', onPressed: widget.onBack),
              const SizedBox(height: AppSpacing.section),
            ],
          ),
        ),
      ),
    );
  }
}

/// NFC 读取成功后的稀有度揭晓（声片鉴定）。
class PressRevealScreen extends StatefulWidget {
  const PressRevealScreen({
    super.key,
    required this.id,
    required this.onBack,
    required this.onConfirm,
  });

  final String id;
  final VoidCallback onBack;
  final VoidCallback onConfirm;

  @override
  State<PressRevealScreen> createState() => _PressRevealScreenState();
}

class _PressRevealScreenState extends State<PressRevealScreen>
    with TickerProviderStateMixin {
  late final AnimationController _unveil;
  late final AnimationController _scan;
  late final AnimationController _tier;
  int _litTier = 0;
  bool _ssrBurst = false;

  DiscRarity get _rarity => PressSession.rarity ?? DiscRarity.n;

  @override
  void initState() {
    super.initState();
    _unveil = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _tier = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _runReveal();
  }

  Future<void> _runReveal() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _tier.forward();
    final target = switch (_rarity) {
      DiscRarity.n => 1,
      DiscRarity.r => 2,
      DiscRarity.sr => 3,
      DiscRarity.ssr => 4,
    };
    for (var i = 1; i <= target; i++) {
      await Future.delayed(const Duration(milliseconds: 280));
      if (!mounted) return;
      setState(() => _litTier = i);
      HapticFeedback.selectionClick();
    }
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    if (_rarity == DiscRarity.ssr) {
      setState(() => _ssrBurst = true);
      HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 80));
      if (mounted) HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.mediumImpact();
    }
    PressSession.markRevealed();
  }

  @override
  void dispose() {
    _unveil.dispose();
    _scan.dispose();
    _tier.dispose();
    super.dispose();
  }

  Color get _accent => RarityHoloStyle.of(_rarity).accent;

  @override
  Widget build(BuildContext context) {
    final item = SoundRepository.instance.get(widget.id);
    final discId = PressSession.discId ?? '—';
    final revealed = _litTier >= switch (_rarity) {
      DiscRarity.n => 1,
      DiscRarity.r => 2,
      DiscRarity.sr => 3,
      DiscRarity.ssr => 4,
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.item),
              const Text(
                '声片鉴定',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 240,
                height: 240,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_unveil, _scan]),
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _RevealAuraPainter(
                        progress: _unveil.value,
                        scan: _scan.value,
                        accent: _accent,
                        intensity: _rarity.index / 3,
                      ),
                      child: Opacity(
                        opacity: Curves.easeOut.transform(_unveil.value),
                        child: Transform.scale(
                          scale: 0.86 + 0.14 * _unveil.value,
                          child: SsrAuraLayer(
                            size: 220,
                            enabled: _rarity == DiscRarity.ssr && revealed,
                            intensity: 1,
                            burst: _ssrBurst,
                            playing: _ssrBurst,
                            energy: _ssrBurst ? 0.9 : 0.35,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                SoundVisualCanvas(
                                  seed: item?.visualSeed ?? 0,
                                  mode: SoundVisualMode.complete,
                                  dark: true,
                                  active: revealed &&
                                      (_rarity == DiscRarity.sr ||
                                          _rarity == DiscRarity.ssr),
                                ),
                                if (revealed)
                                  ClipOval(
                                    child: RarityHoloOverlay(
                                      rarity: _rarity,
                                      intensityScale: 1.0 +
                                          0.2 * (_rarity.index / 3),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              Text(
                revealed ? '声片鉴定完成' : '正在鉴定声片…',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final (i, code) in const [
                    (1, 'N'),
                    (2, 'R'),
                    (3, 'SR'),
                    (4, 'SSR'),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontSize: _litTier == i ? 18 : 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: _litTier >= i
                              ? (i == _litTier && revealed
                                  ? _accent
                                  : Colors.white54)
                              : Colors.white24,
                        ),
                        child: Text(code),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              AnimatedOpacity(
                opacity: revealed ? 1 : 0,
                duration: const Duration(milliseconds: 350),
                child: Column(
                  children: [
                    Text(
                      _rarity.headline,
                      style: TextStyle(
                        color: _accent,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '该稀有度来自声片 No. $discId',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '该稀有度由实体声片决定',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              PrimaryButton(
                text: '确认并永久绑定',
                enabled: revealed,
                onPressed: revealed ? widget.onConfirm : null,
              ),
              const SizedBox(height: AppSpacing.tight),
              SecondaryButton(text: '返回检查', onPressed: widget.onBack),
              const SizedBox(height: AppSpacing.section),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevealAuraPainter extends CustomPainter {
  _RevealAuraPainter({
    required this.progress,
    required this.scan,
    required this.accent,
    required this.intensity,
  });

  final double progress;
  final double scan;
  final Color accent;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.42;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent.withValues(alpha: 0.15 + 0.35 * intensity * progress);
    canvas.drawCircle(c, r + 8, ring);

    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..shader = SweepGradient(
        startAngle: scan * math.pi * 2,
        colors: [
          Colors.transparent,
          accent.withValues(alpha: 0.55),
          Colors.transparent,
        ],
        stops: const [0.0, 0.12, 0.28],
        transform: GradientRotation(scan * math.pi * 2),
      ).createShader(Rect.fromCircle(center: c, radius: r + 16));
    canvas.drawCircle(c, r + 16, sweep);
  }

  @override
  bool shouldRepaint(covariant _RevealAuraPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.scan != scan ||
      oldDelegate.accent != accent;
}

class PressProgressScreen extends StatefulWidget {
  const PressProgressScreen({
    super.key,
    required this.id,
    required this.onDone,
    this.chainOnly = false,
  });

  final String id;
  final VoidCallback onDone;
  final bool chainOnly;

  @override
  State<PressProgressScreen> createState() => _PressProgressScreenState();
}

class _PressProgressScreenState extends State<PressProgressScreen> {
  double _progress = 0;
  String _phase = '准备中…';
  String? _error;
  bool _nfcWritten = false;
  final _cloud = CloudMediaClient();

  static const _phases = [
    '上传音频至云端',
    '云端渲染可视化',
    '写入声片',
    '创建数字资产',
    '加入 Collection',
  ];

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    if (!_nfcWritten && !widget.chainOnly) {
      NfcService.instance.stopSession();
    }
    _cloud.close();
    super.dispose();
  }

  Future<void> _run() async {
    final item = SoundRepository.instance.get(widget.id);
    if (item == null) return;

    SoundRepository.instance.update(
      widget.id,
      (s) => s.copyWith(status: SoundStatus.writing),
    );

    try {
      setState(() {
        _phase = _phases[0];
        _progress = 0.08;
      });

      final token = await AuthService.instance.requireCloudToken();
      await _cloud.assertReachable();
      final ready = await _ensureCloudReady(item, token);

      SoundRepository.instance.update(
        widget.id,
        (s) => s.copyWith(
          contentId: ready.contentId,
          nfcUrl: ready.nfcUrl,
          cloudState: ready.state.wire,
        ),
      );

      if (!widget.chainOnly) {
        setState(() {
          _phase = _phases[2];
          _progress = 0.55;
        });
        final discId = PressSession.discId!;
        final written = await _writeNfc(
          item,
          discId,
          contentId: ready.contentId,
          nfcUrl: ready.nfcUrl,
        );
        if (!written) return;
        _nfcWritten = true;
        SoundRepository.instance.update(
          widget.id,
          (s) => s.copyWith(
            discId: discId,
            nfcTagId: PressSession.tagIdHex,
            discRarity: PressSession.rarity,
            discSeries: PressSession.series,
          ),
        );
        setState(() => _progress = 0.7);
        await Future.delayed(const Duration(milliseconds: 400));
      } else {
        setState(() {
          _progress = 0.7;
          _phase = _phases[3];
        });
      }

      setState(() {
        _progress = 0.85;
        _phase = _phases[3];
      });

      final discId =
          PressSession.discId ?? item.discId ?? NfcService.instance.generateDiscId('RETRY');
      final assetId = await ChainService.instance.submitAsset(
        soundId: widget.id,
        discId: discId,
        rarityCode: (PressSession.rarity ?? item.discRarity)?.code,
        series: PressSession.series ?? item.discSeries,
      );

      setState(() {
        _progress = 1;
        _phase = _phases[4];
      });
      SoundRepository.instance.markCollected(
        widget.id,
        discId,
        assetId,
        nfcTagId: PressSession.tagIdHex ?? item.nfcTagId,
        contentId: ready.contentId,
        nfcUrl: ready.nfcUrl,
        cloudState: ready.state.wire,
        discRarity: PressSession.rarity ?? item.discRarity,
        discSeries: PressSession.series ?? item.discSeries,
      );
      PressSession.clear();
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) widget.onDone();
    } catch (e) {
      final discId = PressSession.discId ?? item.discId;
      if (_nfcWritten || widget.chainOnly) {
        SoundRepository.instance.markChainFailed(
          widget.id,
          discId ?? 'SP-UNKNOWN',
          nfcTagId: PressSession.tagIdHex ?? item.nfcTagId,
          discRarity: PressSession.rarity ?? item.discRarity,
          discSeries: PressSession.series ?? item.discSeries,
        );
      } else {
        SoundRepository.instance.markWriteFailed(widget.id);
      }
      if (mounted) {
        setState(() {
          _error = e.toString();
          _phase = '失败';
        });
      }
    }
  }

  Future<ContentSummary> _ensureCloudReady(SoundMemory item, String token) async {
    var contentId = item.contentId;

    if (contentId != null && contentId.isNotEmpty) {
      var summary = await _cloud.getContent(token: token, contentId: contentId);
      if (summary.state == CloudContentState.ready) {
        setState(() {
          _phase = _phases[1];
          _progress = 0.5;
        });
        return summary;
      }
      if (summary.state == CloudContentState.failed) {
        setState(() {
          _phase = '重试云端处理…';
          _progress = 0.2;
        });
        summary = await _cloud.retryContent(token: token, contentId: contentId);
      }
      if (summary.state == CloudContentState.ready) return summary;
      setState(() {
        _phase = _phases[1];
        _progress = 0.25;
      });
      return _cloud.waitUntilReady(
        token: token,
        contentId: contentId,
        onUpdate: (s) {
          if (!mounted) return;
          setState(() {
            _phase = '云端处理：${s.state.wire}';
            _progress = s.state == CloudContentState.processing ? 0.4 : 0.3;
          });
        },
      );
    }

    final path = item.audioPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      throw StateError('缺少本地录音文件，无法上传云端');
    }

    setState(() {
      _phase = '正在准备可视化帧序列…';
      _progress = 0.1;
    });
    final created = await uploadSoundPackage(
      cloud: _cloud,
      item: item,
      token: token,
      onStatus: (status) {
        if (!mounted) return;
        setState(() {
          _phase = status;
          _progress = status.contains('上传') ? 0.18 : 0.12;
        });
      },
    );
    contentId = created.contentId;
    SoundRepository.instance.update(
      widget.id,
      (s) => s.copyWith(contentId: contentId, cloudState: created.state.wire),
    );

    setState(() {
      _phase = _phases[1];
      _progress = 0.28;
    });
    return _cloud.waitUntilReady(
      token: token,
      contentId: contentId,
      onUpdate: (s) {
        if (!mounted) return;
        setState(() {
          _phase = '云端处理：${s.state.wire}';
          _progress = s.state == CloudContentState.processing ? 0.42 : 0.32;
        });
      },
    );
  }

  Future<bool> _writeNfc(
    SoundMemory item,
    String discId, {
    required String contentId,
    String? nfcUrl,
  }) async {
    final completer = Completer<bool>();
    await NfcService.instance.startSession(
      alertMessage: '保持手机贴近声片，正在写入…',
      invalidateAfterFirstRead: false,
      onDiscovered: (tag) async {
        try {
          await NfcService.instance.writeBinding(
            tag: tag,
            soundId: widget.id,
            discId: discId,
            title: item.title,
            contentId: contentId,
            nfcUrl: nfcUrl,
            rarity: PressSession.rarity ?? item.discRarity,
            series: PressSession.series ?? item.discSeries,
            factory: PressSession.rarity == null
                ? null
                : DiscFactoryProfile(
                    discId: discId,
                    rarity: PressSession.rarity!,
                    series: PressSession.series ?? 'Unknown',
                    signature: PressSession.factorySignature ??
                        DiscFactoryProfile.computeSignature(
                          discId: discId,
                          rarity: PressSession.rarity!,
                          series: PressSession.series ?? 'Unknown',
                          demo: PressSession.factoryDemo,
                        ),
                    bound: true,
                    demo: PressSession.factoryDemo,
                  ),
          );
          await NfcService.instance.stopSession(message: '写入成功');
          if (!completer.isCompleted) completer.complete(true);
        } catch (e) {
          await NfcService.instance.stopSession(error: '写入失败');
          if (!completer.isCompleted) completer.completeError(e);
        }
      },
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 45));
    } on TimeoutException {
      await NfcService.instance.stopSession();
      throw StateError('写入超时，请保持手机贴近声片后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = SoundRepository.instance.get(widget.id);
    return PopScope(
      canPop: _error != null,
      child: Scaffold(
        backgroundColor: AppColors.darkCanvas,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: SoundVisualCanvas(
                      seed: item?.visualSeed ?? 0,
                      active: _error == null,
                      dark: true,
                      showProgressRing: true,
                      progress: _progress,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  Text(
                    _error ?? _phase,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _error != null ? AppColors.error : AppColors.darkText),
                  ),
                  if (_error == null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${(_progress * 100).round()}%',
                      style: const TextStyle(color: AppColors.primary500, fontSize: 24),
                    ),
                    const SizedBox(height: AppSpacing.item),
                    const Text(
                      '请保持手机靠近声片，不要关闭 App',
                      style: TextStyle(color: AppColors.darkSecondary, fontSize: 13),
                    ),
                  ] else ...[
                    const SizedBox(height: AppSpacing.section),
                    PrimaryButton(
                      text: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 写入完成终章：NFC 写入 + 上链均成功后，先以 3D 翻面动画封存声片，
/// 揭示背面的 NFT 稀有度卡，随后卡片永久保持展示。
class PressDoneScreen extends StatefulWidget {
  const PressDoneScreen({
    super.key,
    required this.id,
    required this.onCollection,
    required this.onOpenCategoryPlay,
  });

  final String id;
  final VoidCallback onCollection;
  final ValueChanged<String> onOpenCategoryPlay;

  @override
  State<PressDoneScreen> createState() => _PressDoneScreenState();
}

class _PressDoneScreenState extends State<PressDoneScreen>
    with SingleTickerProviderStateMixin {
  static const _cardWidth = 300.0;
  static const _cardHeight = 460.0;

  late final AnimationController _flip;
  late final Animation<double> _flipCurve;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _flipCurve = CurvedAnimation(parent: _flip, curve: Curves.easeOutCubic);
    _flip.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_revealed) {
        setState(() => _revealed = true);
        HapticFeedback.mediumImpact();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 260), () {
        if (mounted) _flip.forward();
      });
    });
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = SoundRepository.instance.get(widget.id);
    if (item == null) {
      return _buildFallback();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                width: _cardWidth,
                height: _cardHeight,
                child: AnimatedBuilder(
                  animation: _flipCurve,
                  builder: (context, _) {
                    final angle = _flipCurve.value * math.pi;
                    final showFront = angle < math.pi / 2;
                    final transform = Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateY(angle);
                    return Transform(
                      alignment: Alignment.center,
                      transform: transform,
                      child: showFront
                          ? const _CardFrontFace()
                          : Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()..rotateY(math.pi),
                              child: _CardBackFace(
                                item: item,
                                animate: _revealed,
                              ),
                            ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              AnimatedOpacity(
                opacity: _revealed ? 1 : 0,
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOut,
                child: const Text(
                  '写入完成 · 数字资产已生成',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const Spacer(),
              AnimatedOpacity(
                opacity: _revealed ? 1 : 0,
                duration: const Duration(milliseconds: 420),
                child: IgnorePointer(
                  ignoring: !_revealed,
                  child: Column(
                    children: [
                      PrimaryButton(
                        text: '返回 Collection',
                        onPressed: widget.onCollection,
                      ),
                      const SizedBox(height: AppSpacing.tight),
                      SecondaryButton(
                        text: '查看声片记忆',
                        onPressed: () => widget.onOpenCategoryPlay(item.category),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.section),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: Column(
            children: [
              const Spacer(),
              const Text(
                '写入完成',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '未找到该声片的记录',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
              ),
              const Spacer(),
              PrimaryButton(text: '返回 Collection', onPressed: widget.onCollection),
              const SizedBox(height: AppSpacing.section),
            ],
          ),
        ),
      ),
    );
  }
}

/// 翻面动画正面：深色玻璃封片，隐去内容直到揭晓。
class _CardFrontFace extends StatelessWidget {
  const _CardFrontFace();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface2, Colors.black],
        ),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.graphic_eq_rounded,
                color: AppColors.accent,
                size: 24,
              ),
            ),
            const SizedBox(height: AppSpacing.section),
            const Text(
              'SoundPola',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '声片已封存',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 翻面动画背面：NFT 稀有度卡，动画结束后永久展示。
class _CardBackFace extends StatelessWidget {
  const _CardBackFace({required this.item, required this.animate});

  final SoundMemory item;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SoundNftCard(item: item, animateVisual: animate),
    );
  }
}
