import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/session.dart';
import '../../data/sound_repository.dart';
import '../../services/nfc_service.dart';
import '../../services/visual_shape_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/sound_visual.dart';

class PressMethodScreen extends StatefulWidget {
  const PressMethodScreen({
    super.key,
    required this.id,
    required this.onBack,
    required this.onNfc,
  });

  final String id;
  final VoidCallback onBack;
  final VoidCallback onNfc;

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
            '选择写入方式，让这段声音与 NFC 声片相伴。',
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
          const _MethodCard(
            title: '硬件设备写入',
            subtitle: '即将推出',
            enabled: false,
            onTap: _noop,
          ),
        ],
      ),
    );
  }

  static void _noop() {}

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
                          child: SoundVisualCanvas(
                            seed: item.visualSeed,
                            active: false,
                            shape: VisualShapeService.instance
                                .peek(item.visualPath),
                          ),
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
                  _message = '该声片已绑定，无法覆盖';
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
            _handled = true;
            final discId = SoundRepository.instance.get(widget.id)?.discId ??
                NfcService.instance.generateDiscId(tagId);
            PressSession.set(tagId: tagId, disc: discId);
            await NfcService.instance.stopSession(message: '声片已识别');
            if (mounted) {
              setState(() {
                _state = _DetectState.ready;
                _message = '空白声片 · $discId';
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
    return Scaffold(
      backgroundColor: AppColors.canvasBg,
      appBar: AppBar(
        backgroundColor: AppColors.canvasBg,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        title: const Text('写入声片确认'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item != null)
                        SizedBox(
                          height: 160,
                          child: SoundVisualCanvas(
                            seed: item.visualSeed,
                            active: false,
                            shape: VisualShapeService.instance
                                .peek(item.visualPath),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.item),
                      if (item != null) ...[
                        Text(item.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                        Text('#${item.category}', style: const TextStyle(color: AppColors.ink600)),
                      ],
                      const SizedBox(height: AppSpacing.item),
                      MetaRow(label: '声片编号', value: discId),
                      MetaRow(label: '写入方式', value: '手机 NFC'),
                      const SizedBox(height: AppSpacing.item),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.tight),
                        decoration: BoxDecoration(
                          color: AppColors.primary50,
                          borderRadius: BorderRadius.circular(AppRadii.card),
                        ),
                        child: const Text(
                          '写入完成后，这段声音将与手中的声片相伴，随时贴近即可再次听见。',
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
                    ],
                  ),
                ),
              ),
              PrimaryButton(
                text: '确认并写入',
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

class PressProgressScreen extends StatefulWidget {
  const PressProgressScreen({
    super.key,
    required this.id,
    required this.onDone,
  });

  final String id;
  final VoidCallback onDone;

  @override
  State<PressProgressScreen> createState() => _PressProgressScreenState();
}

enum _PressPhase { idle, waitingContact, writing, finalizing, done, error }

class _PressProgressScreenState extends State<PressProgressScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressAnim;
  _PressPhase _phase = _PressPhase.idle;
  String _statusText = '准备中…';
  String? _error;
  bool _timedOut = false;
  bool _nfcWritten = false;
  Timer? _contactTimeoutTimer;

  static const _contactTimeout = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _progressAnim = AnimationController(
      vsync: this,
      value: 0,
      duration: const Duration(milliseconds: 300),
    );
    _run();
  }

  @override
  void dispose() {
    _contactTimeoutTimer?.cancel();
    _progressAnim.dispose();
    if (!_nfcWritten) {
      NfcService.instance.stopSession();
    }
    super.dispose();
  }

  Future<void> _run() async {
    final item = SoundRepository.instance.get(widget.id);
    if (item == null) return;

    final contentId = item.contentId;
    final discId = PressSession.discId ?? item.discId;
    if (contentId == null || contentId.isEmpty || discId == null) {
      _setError('请先完成上链');
      return;
    }

    setState(() {
      _phase = _PressPhase.waitingContact;
      _statusText = '等待贴合声片…';
      _timedOut = false;
      _error = null;
    });
    _progressAnim.value = 0.05;
    _progressAnim.animateTo(0.15, duration: const Duration(milliseconds: 900));

    try {
      final written = await _writeNfc(
        item,
        discId,
        contentId: contentId,
        nfcUrl: item.nfcUrl,
      );
      if (!written) return;
      _nfcWritten = true;

      setState(() {
        _phase = _PressPhase.finalizing;
        _statusText = '加入 Collection…';
      });
      await _progressAnim.animateTo(
        0.95,
        duration: const Duration(milliseconds: 350),
      );

      SoundRepository.instance.markCollected(
        widget.id,
        discId,
        item.assetId ?? discId,
        nfcTagId: PressSession.tagIdHex ?? item.nfcTagId,
        contentId: contentId,
        nfcUrl: item.nfcUrl,
        cloudState: item.cloudState ?? 'READY',
      );
      PressSession.clear();
      await _progressAnim.animateTo(
        1.0,
        duration: const Duration(milliseconds: 250),
      );
      setState(() {
        _phase = _PressPhase.done;
        _statusText = '完成';
      });
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) widget.onDone();
    } catch (e) {
      if (!mounted) return;
      _setError(e.toString());
    }
  }

  void _setError(String message) {
    _contactTimeoutTimer?.cancel();
    setState(() {
      _error = message;
      _phase = _PressPhase.error;
      _statusText = '失败';
    });
    _progressAnim.stop();
  }

  Future<bool> _writeNfc(
    SoundMemory item,
    String discId, {
    required String contentId,
    String? nfcUrl,
  }) async {
    final completer = Completer<bool>();
    _contactTimeoutTimer?.cancel();
    _contactTimeoutTimer = Timer(_contactTimeout, () async {
      if (completer.isCompleted) return;
      _timedOut = true;
      await NfcService.instance.stopSession();
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('未检测到声片，请把手机背面贴合声片后重试'),
        );
      }
    });
    await NfcService.instance.startSession(
      alertMessage: '保持手机贴近声片，正在写入…',
      invalidateAfterFirstRead: false,
      onDiscovered: (tag) async {
        _contactTimeoutTimer?.cancel();
        if (mounted && _phase == _PressPhase.waitingContact) {
          setState(() {
            _phase = _PressPhase.writing;
            _statusText = '写入声片中…';
          });
          _progressAnim.animateTo(
            0.85,
            duration: const Duration(milliseconds: 2200),
            curve: Curves.easeOut,
          );
        }
        try {
          await NfcService.instance.writeBinding(
            tag: tag,
            soundId: widget.id,
            discId: discId,
            title: item.title,
            contentId: contentId,
            nfcUrl: nfcUrl,
          );
          await NfcService.instance.stopSession(message: '写入成功');
          if (!completer.isCompleted) completer.complete(true);
        } catch (e) {
          await NfcService.instance.stopSession(error: '写入失败');
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('声片写入失败：${e.toString()}'),
            );
          }
        }
      },
    );
    return completer.future;
  }

  void _retry() {
    setState(() {
      _error = null;
      _timedOut = false;
      _phase = _PressPhase.idle;
      _statusText = '准备中…';
    });
    _progressAnim.value = 0;
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final item = SoundRepository.instance.get(widget.id);
    final waiting = _phase == _PressPhase.waitingContact;
    return PopScope(
      canPop: _error != null || _phase == _PressPhase.done,
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
                    width: 240,
                    height: 240,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (waiting)
                          const Positioned.fill(
                            child: NfcRippleVisual(active: true),
                          ),
                        AnimatedBuilder(
                          animation: _progressAnim,
                          builder: (_, _) => SizedBox(
                            width: 220,
                            height: 220,
                            child: SoundVisualCanvas(
                              seed: item?.visualSeed ?? 0,
                              active: _error == null,
                              dark: true,
                              showProgressRing: !waiting,
                              progress: _progressAnim.value,
                              shape: VisualShapeService.instance
                                  .peek(item?.visualPath),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  Text(
                    _error ?? _statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _error != null
                          ? AppColors.error
                          : AppColors.darkText,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_error == null) ...[
                    const SizedBox(height: 8),
                    if (!waiting)
                      AnimatedBuilder(
                        animation: _progressAnim,
                        builder: (_, _) => Text(
                          '${(_progressAnim.value * 100).round()}%',
                          style: const TextStyle(
                            color: AppColors.primary500,
                            fontSize: 24,
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.item),
                    Text(
                      waiting
                          ? '请将手机背面贴合空白声片\n感应到后会自动开始写入'
                          : '请保持手机靠近声片，不要关闭 App',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.darkSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ] else ...[
                    if (_timedOut) ...[
                      const SizedBox(height: 8),
                      const Text(
                        '感应超时。请贴紧手机背面 NFC 感应区。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.darkSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.section),
                    PrimaryButton(
                      text: '重试',
                      onPressed: _retry,
                    ),
                    const SizedBox(height: AppSpacing.tight),
                    SecondaryButton(
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

class PressDoneScreen extends StatelessWidget {
  const PressDoneScreen({
    super.key,
    required this.id,
    required this.onCollection,
    required this.onMemory,
  });

  final String id;
  final VoidCallback onCollection;
  final VoidCallback onMemory;

  @override
  Widget build(BuildContext context) {
    final item = SoundRepository.instance.get(id);
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                height: 160,
                child: SoundVisualCanvas(
                  seed: item?.visualSeed ?? 999,
                  mode: SoundVisualMode.complete,
                  shape: VisualShapeService.instance
                      .peek(item?.visualPath),
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              const Text(
                '写入完成',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item?.title ?? '',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (item?.discId != null) ...[
                const SizedBox(height: 8),
                Text(
                  '声片 ${item!.discId}',
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                ),
              ],
              if (item?.assetId != null) ...[
                const SizedBox(height: 4),
                Text(
                  '数字资产 ${item!.assetId}',
                  style: const TextStyle(color: AppColors.accent, fontSize: 13),
                ),
              ],
              if (item?.chainedAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  '上链 ${formatRecordedAt(item!.chainedAt!)}',
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                ),
              ],
              const Spacer(),
              PrimaryButton(text: '返回 Collection', onPressed: onCollection),
              const SizedBox(height: AppSpacing.tight),
              SecondaryButton(text: '打开 Memory', onPressed: onMemory),
              const SizedBox(height: AppSpacing.section),
            ],
          ),
        ),
      ),
    );
  }
}
