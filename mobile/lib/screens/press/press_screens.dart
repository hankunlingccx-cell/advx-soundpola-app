import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../cloud/cloud_media_client.dart';
import '../../cloud/cloud_media_models.dart';
import '../../data/session.dart';
import '../../data/sound_repository.dart';
import '../../services/auth_service.dart';
import '../../services/chain_service.dart';
import '../../services/nfc_service.dart';
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
            final discId = NfcService.instance.generateDiscId(tagId);
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
              MetaRow(label: '写入方式', value: '手机 NFC'),
              const SizedBox(height: AppSpacing.item),
              Container(
                padding: const EdgeInsets.all(AppSpacing.tight),
                decoration: BoxDecoration(
                  color: AppColors.primary50,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: const Text(
                  '每张声片只能写入一个声音。写入完成后，声音和声片将永久绑定，无法替换或覆盖。',
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
          (s) => s.copyWith(discId: discId, nfcTagId: PressSession.tagIdHex),
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
      _phase = _phases[0];
      _progress = 0.15;
    });
    final created = await _cloud.uploadAudio(
      token: token,
      file: File(path),
      filename: path.split(Platform.pathSeparator).last,
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
