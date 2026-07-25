import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../data/disc_rarity.dart';
import '../../data/session.dart';
import '../../data/sound_repository.dart';
import '../../services/auth_service.dart';
import '../../services/audio_playback_service.dart';
import '../../services/nfc_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/sound_visual.dart';
import '../../widgets/sp_category_picker.dart';
import 'draft_tray_carousel.dart';
import 'nfc_guide_panel.dart';
import 'press_machine.dart';

enum _DragPhase { idle, dragging, snapping, inserting, retrieving }

enum _FlowPhase {
  idle,
  waitingNfc,
  found,
  pressing,
  complete,
  interrupted,
  alreadyBound,
}

class DraftsScreen extends StatefulWidget {
  const DraftsScreen({
    super.key,
    required this.onOpenDetail,
    required this.onStartRecord,
    required this.onOpenCollection,
    required this.onLogin,
  });

  final ValueChanged<String> onOpenDetail;
  final VoidCallback onStartRecord;
  final VoidCallback onOpenCollection;
  final VoidCallback onLogin;

  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  PressMachineMode _machineMode = PressMachineMode.idle;
  _DragPhase _dragPhase = _DragPhase.idle;
  _FlowPhase _flow = _FlowPhase.idle;

  Offset? _dragGlobal;
  int? _dragIndex;
  double _dragScale = 1;
  double _dragAngle = 0;
  /// 0 = 完全可见，1 = 完全吸入插槽。
  double _insertProgress = 0;

  String? _loadedId;
  SoundMemory? _loadedItem;
  double _pressProgress = 0;
  bool _autoListening = false;
  bool _chaining = false;
  bool _nfcBusy = false;

  late final AnimationController _breath;
  final GlobalKey _slotKey = GlobalKey();
  final GlobalKey _stageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    NfcService.instance.stopSession();
    _breath.dispose();
    super.dispose();
  }

  List<SoundMemory> get _allDrafts => SoundRepository.instance.drafts;

  List<SoundMemory> get _trayItems {
    final id = _loadedId;
    if (id == null) return _allDrafts;
    return _allDrafts.where((s) => s.id != id).toList();
  }

  bool get _inSession =>
      _flow != _FlowPhase.idle ||
      _dragPhase == _DragPhase.inserting ||
      _dragPhase == _DragPhase.retrieving;

  bool get _trayLocked =>
      _inSession ||
      _dragPhase == _DragPhase.dragging ||
      _dragPhase == _DragPhase.snapping ||
      _flow == _FlowPhase.pressing ||
      _flow == _FlowPhase.found;

  NfcGuidePhase get _guidePhase {
    if (_allDrafts.isEmpty && _flow == _FlowPhase.idle) {
      return NfcGuidePhase.empty;
    }
    if (_dragPhase == _DragPhase.dragging ||
        _dragPhase == _DragPhase.snapping ||
        _dragPhase == _DragPhase.inserting) {
      return NfcGuidePhase.dimmed;
    }
    return switch (_flow) {
      _FlowPhase.idle => NfcGuidePhase.howto,
      _FlowPhase.waitingNfc => NfcGuidePhase.waiting,
      _FlowPhase.found => NfcGuidePhase.found,
      _FlowPhase.pressing => NfcGuidePhase.pressing,
      _FlowPhase.complete => NfcGuidePhase.complete,
      _FlowPhase.interrupted => NfcGuidePhase.interrupted,
      _FlowPhase.alreadyBound => NfcGuidePhase.alreadyBound,
    };
  }

  bool _canPress(SoundMemory item) =>
      item.status == SoundStatus.drafted ||
      item.status == SoundStatus.writeFailed ||
      item.status == SoundStatus.chainFailed;

  Rect? _slotRectGlobal() {
    final box = _slotKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      topLeft.dx - 40,
      topLeft.dy - 56,
      box.size.width + 80,
      box.size.height + 110,
    );
  }

  Rect? _stageRectGlobal() {
    final box = _stageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _syncMachineIdle() {
    _machineMode =
        _allDrafts.isEmpty ? PressMachineMode.empty : PressMachineMode.idle;
  }

  // ─── Drag ───────────────────────────────────────────

  void _onLongPressCenter(LongPressStartDetails details, int index) {
    if (_trayLocked || _flow != _FlowPhase.idle) return;
    final items = _trayItems;
    if (index < 0 || index >= items.length) return;
    if (!_canPress(items[index])) {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _dragPhase = _DragPhase.dragging;
      _dragIndex = index;
      _dragGlobal = details.globalPosition;
      _dragScale = 1.04;
      _dragAngle = 0;
      _insertProgress = 0;
      _machineMode = PressMachineMode.receiving;
    });
  }

  void _onLongPressMove(LongPressMoveUpdateDetails details) {
    if (_dragPhase != _DragPhase.dragging) return;
    final next = details.globalPosition;
    final slot = _slotRectGlobal();
    var mode = PressMachineMode.receiving;
    var scale = 1.04;
    var angle = 0.0;
    var near = false;

    if (slot != null) {
      final dist = (next - slot.center).distance;
      final t = (1 - (dist / 280)).clamp(0.0, 1.0);
      scale = uiLerp(1.04, 0.94, t);
      angle = uiLerp(_dragAngle, 0.02, t * 0.5);
      if (slot.contains(next) || dist < 95) {
        mode = PressMachineMode.readyToRelease;
        near = true;
        scale = 0.92;
        angle = 0;
      }
    }

    final wasReady = _machineMode == PressMachineMode.readyToRelease;
    setState(() {
      _dragGlobal = next;
      _dragScale = scale;
      _dragAngle = angle;
      _machineMode = mode;
    });
    if (near && !wasReady) HapticFeedback.lightImpact();
  }

  Future<void> _onLongPressEnd(LongPressEndDetails details) async {
    if (_dragPhase != _DragPhase.dragging || _dragIndex == null) return;
    final slot = _slotRectGlobal();
    final pos = details.globalPosition;
    final inZone = slot != null &&
        (slot.contains(pos) || (pos - slot.center).distance < 100);
    if (!inZone) {
      await _springBack();
      return;
    }
    await _runInsertAnimation();
  }

  Future<void> _springBack() async {
    setState(() {
      _dragPhase = _DragPhase.snapping;
      _insertProgress = 0;
    });
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    setState(() {
      _dragPhase = _DragPhase.idle;
      _dragIndex = null;
      _dragGlobal = null;
      _dragScale = 1;
      _dragAngle = 0;
      _syncMachineIdle();
    });
  }

  /// 650–900ms 连续插卡：吸附 → 停顿 → 吸入遮挡 → 闭合。
  Future<void> _runInsertAnimation() async {
    final items = _trayItems;
    final index = _dragIndex;
    final slot = _slotRectGlobal();
    if (index == null || index >= items.length || slot == null) {
      await _springBack();
      return;
    }
    final item = items[index];

    HapticFeedback.mediumImpact();
    // 1) 快速吸附到插槽中心
    setState(() {
      _dragPhase = _DragPhase.snapping;
      _dragGlobal = slot.center.translate(0, 8);
      _dragScale = 0.9;
      _dragAngle = 0;
      _insertProgress = 0.05;
      _machineMode = PressMachineMode.readyToRelease;
    });
    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;

    // 2) 短暂停顿 80–120ms
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    // 3) 沿插槽吸入，逐步遮挡
    setState(() {
      _dragPhase = _DragPhase.inserting;
      _machineMode = PressMachineMode.inserting;
    });

    const steps = 8;
    for (var i = 1; i <= steps; i++) {
      if (!mounted) return;
      final t = i / steps;
      final eased = Curves.easeInCubic.transform(t);
      setState(() {
        _insertProgress = eased;
        _dragGlobal = Offset(
          slot.center.dx,
          slot.center.dy - 18 - eased * 56,
        );
        _dragScale = uiLerp(0.9, 0.78, eased);
      });
      await Future<void>.delayed(const Duration(milliseconds: 55));
    }
    if (!mounted) return;

    // 4) 插槽收紧 + 短促扫描感
    setState(() {
      _dragPhase = _DragPhase.idle;
      _dragIndex = null;
      _dragGlobal = null;
      _insertProgress = 1;
      _loadedId = item.id;
      _loadedItem = item;
      _flow = _FlowPhase.waitingNfc;
      _machineMode = PressMachineMode.loaded;
      _pressProgress = 0;
    });
    HapticFeedback.selectionClick();

    // 登录前置
    if (!AuthService.instance.isLoggedIn) {
      widget.onLogin();
    }
  }

  Future<void> _retrieveSound() async {
    if (_flow == _FlowPhase.pressing || _flow == _FlowPhase.found) return;
    if (_loadedItem == null) return;

    await NfcService.instance.stopSession();
    _autoListening = false;

    final slot = _slotRectGlobal();
    final item = _loadedItem!;
    final tray = _trayItems;
    // 插回轮播：恢复到列表中（本来就在 repo，只是隐藏）
    final insertAt = _selectedIndex.clamp(0, tray.length);

    setState(() {
      _dragPhase = _DragPhase.retrieving;
      _machineMode = PressMachineMode.receiving;
      _flow = _FlowPhase.idle;
      _dragGlobal = slot?.center ?? Offset.zero;
      _dragScale = 0.82;
      _insertProgress = 0.85;
      _dragIndex = null;
    });

    // 边缘露出 → 推出三分之一 → 回中央
    if (slot != null) {
      for (var i = 1; i <= 6; i++) {
        if (!mounted) return;
        final t = i / 6;
        setState(() {
          _insertProgress = uiLerp(0.85, 0, t);
          _dragGlobal = Offset(
            slot.center.dx,
            slot.center.dy + t * 120,
          );
          _dragScale = uiLerp(0.82, 1.0, t);
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    if (!mounted) return;
    setState(() {
      _dragPhase = _DragPhase.idle;
      _dragGlobal = null;
      _insertProgress = 0;
      _loadedId = null;
      _loadedItem = null;
      _selectedIndex = insertAt;
      // 把取回的声音放回视觉队列后选中它
      final idx = _trayItems.indexWhere((s) => s.id == item.id);
      if (idx >= 0) _selectedIndex = idx;
      _syncMachineIdle();
    });
  }

  // ─── NFC ────────────────────────────────────────────

  Future<void> _startNfcDetect({bool auto = false}) async {
    if (_loadedItem == null || _nfcBusy) return;
    if (!AuthService.instance.isLoggedIn) {
      widget.onLogin();
      return;
    }

    final status = await NfcService.instance.checkStatus();
    if (status != NfcDeviceStatus.available) {
      // 开发机 / 无 NFC：模拟检测写入，保证流程可走通
      if (kDebugMode || status == NfcDeviceStatus.unavailable) {
        await _simulatePress();
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == NfcDeviceStatus.disabled ? '请先开启 NFC' : '本机不支持 NFC',
          ),
          action: status == NfcDeviceStatus.disabled
              ? SnackBarAction(
                  label: '设置',
                  onPressed: NfcService.instance.openNfcSettings,
                )
              : null,
        ),
      );
      return;
    }

    setState(() {
      _autoListening = auto;
      _flow = _FlowPhase.waitingNfc;
      _machineMode = PressMachineMode.loaded;
    });

    _nfcBusy = true;
    try {
      await NfcService.instance.startSession(
        alertMessage: '将手机背面靠近声片',
        onDiscovered: _onTagDiscovered,
      );
    } catch (e) {
      _nfcBusy = false;
      if (mounted) {
        setState(() {
          _flow = _FlowPhase.interrupted;
          _machineMode = PressMachineMode.interrupted;
          _autoListening = false;
        });
      }
    }
  }

  Future<void> _onTagDiscovered(NfcTag tag) async {
    if (_loadedItem == null) return;
    try {
      final binding = await NfcService.instance.readBinding(tag);
      if (binding != null) {
        await NfcService.instance.stopSession();
        _nfcBusy = false;
        if (!mounted) return;
        HapticFeedback.mediumImpact();
        setState(() {
          _flow = _FlowPhase.alreadyBound;
          _machineMode = PressMachineMode.alreadyBound;
          _autoListening = false;
        });
        return;
      }

      if (!await NfcService.instance.canWriteTag(tag)) {
        if (mounted) {
          setState(() {
            _flow = _FlowPhase.interrupted;
            _machineMode = PressMachineMode.interrupted;
          });
        }
        return;
      }

      var factory = await NfcService.instance.readFactoryProfile(tag);
      factory ??= DiscFactoryProfile.demoFromTagId(
        NfcService.instance.tagIdHex(tag),
      );
      if (factory.bound) {
        await NfcService.instance.stopSession();
        _nfcBusy = false;
        if (!mounted) return;
        setState(() {
          _flow = _FlowPhase.alreadyBound;
          _machineMode = PressMachineMode.alreadyBound;
          _autoListening = false;
        });
        return;
      }

      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() {
          _flow = _FlowPhase.found;
          _machineMode = PressMachineMode.found;
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (!mounted) return;

      PressSession.set(
        tagId: NfcService.instance.tagIdHex(tag),
        disc: factory.discId,
        discRarity: factory.rarity,
        discSeries: factory.series,
        signature: factory.signature,
        demo: factory.demo,
      );

      await _writeAndSeal(tag, factory);
    } catch (_) {
      await NfcService.instance.stopSession(error: '写入失败');
      _nfcBusy = false;
      if (mounted) {
        setState(() {
          _flow = _FlowPhase.interrupted;
          _machineMode = PressMachineMode.interrupted;
          _autoListening = false;
        });
      }
    }
  }

  Future<void> _writeAndSeal(NfcTag tag, DiscFactoryProfile factory) async {
    final item = _loadedItem;
    if (item == null) return;

    setState(() {
      _flow = _FlowPhase.pressing;
      _machineMode = PressMachineMode.pressing;
      _pressProgress = 0.08;
    });

    // 分段进度（真实写入前后），禁止无限转圈
    for (final p in [0.22, 0.38, 0.52]) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      setState(() => _pressProgress = p);
    }

    try {
      await NfcService.instance.writeBinding(
        tag: tag,
        soundId: item.id,
        discId: factory.discId,
        title: item.title,
        rarity: factory.rarity,
        series: factory.series,
        factory: factory.copyWith(bound: true),
      );
      await NfcService.instance.stopSession(message: '写入成功');
    } catch (_) {
      await NfcService.instance.stopSession(error: '写入失败');
      _nfcBusy = false;
      if (mounted) {
        setState(() {
          _flow = _FlowPhase.interrupted;
          _machineMode = PressMachineMode.interrupted;
        });
      }
      return;
    }

    for (final p in [0.72, 0.88, 1.0]) {
      await Future<void>.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
      setState(() => _pressProgress = p);
    }

    final assetId = 'asset_${item.id}';
    SoundRepository.instance.markCollected(
      item.id,
      factory.discId,
      assetId,
      nfcTagId: PressSession.tagIdHex,
      discRarity: factory.rarity,
      discSeries: factory.series,
    );

    _nfcBusy = false;
    PressSession.clear();
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() {
      _flow = _FlowPhase.complete;
      _machineMode = PressMachineMode.complete;
      _chaining = true;
      _loadedId = null;
      _autoListening = false;
    });
    // 资产生成中提示短暂后可视为已可查看
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _chaining = false);
    });
  }

  Future<void> _simulatePress() async {
    final item = _loadedItem;
    if (item == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _flow = _FlowPhase.found;
      _machineMode = PressMachineMode.found;
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() {
      _flow = _FlowPhase.pressing;
      _machineMode = PressMachineMode.pressing;
      _pressProgress = 0;
    });
    for (var i = 1; i <= 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
      setState(() => _pressProgress = i / 12);
    }
    final discId = NfcService.instance.generateDiscId('DEMO');
    final rarity = DiscRarity.values[item.visualSeed % DiscRarity.values.length];
    SoundRepository.instance.markCollected(
      item.id,
      discId,
      'asset_${item.id}',
      discRarity: rarity,
      discSeries: 'Genesis-Sim',
    );
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() {
      _flow = _FlowPhase.complete;
      _machineMode = PressMachineMode.complete;
      _chaining = true;
      _loadedId = null;
      _loadedItem = item;
    });
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _chaining = false);
    });
  }

  Future<void> _cancelNfc() async {
    await NfcService.instance.stopSession();
    _nfcBusy = false;
    if (!mounted) return;
    setState(() {
      _autoListening = false;
      _flow = _FlowPhase.waitingNfc;
      _machineMode = PressMachineMode.loaded;
    });
  }

  void _continueAfterComplete() {
    setState(() {
      _flow = _FlowPhase.idle;
      _loadedItem = null;
      _loadedId = null;
      _pressProgress = 0;
      _chaining = false;
      _syncMachineIdle();
      if (_trayItems.isNotEmpty) {
        _selectedIndex = 0;
      }
    });
  }

  // ─── Build ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        SoundRepository.instance,
        AuthService.instance,
      ]),
      builder: (context, _) {
        final tray = _trayItems;
        final count = _allDrafts.length;
        final countLabel = count.toString().padLeft(2, '0');
        final selected = tray.isEmpty
            ? 0
            : _selectedIndex.clamp(0, tray.length - 1).toInt();
        if (selected != _selectedIndex && tray.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedIndex = selected);
          });
        }

        if (_flow == _FlowPhase.idle &&
            _dragPhase == _DragPhase.idle &&
            _loadedId == null) {
          final next = count == 0 ? PressMachineMode.empty : PressMachineMode.idle;
          if (_machineMode != next &&
              (_machineMode == PressMachineMode.idle ||
                  _machineMode == PressMachineMode.empty ||
                  _machineMode == PressMachineMode.complete)) {
            _machineMode = next;
          }
        }

        final loggedIn = AuthService.instance.isLoggedIn;
        final dragging = _dragPhase == _DragPhase.dragging ||
            _dragPhase == _DragPhase.inserting ||
            _dragPhase == _DragPhase.retrieving;

        return ColoredBox(
          color: AppColors.bgPrimary,
          child: SafeArea(
            bottom: false,
            child: Stack(
              key: _stageKey,
              clipBehavior: Clip.none,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 16, 4),
                      child: AnimatedOpacity(
                        duration: AppMotion.fast,
                        opacity: dragging ? 0.32 : 1,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'SOUND DRAFTS · $countLabel',
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 34,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: -0.6,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    '待封存的声音',
                                    style: TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!loggedIn)
                              _CompactAccountButton(
                                icon: Icons.person_outline,
                                onTap: widget.onLogin,
                              )
                            else
                              const AccountAvatarButton(compact: true),
                          ],
                        ),
                      ),
                    ),
                    if (!loggedIn && _flow == _FlowPhase.idle)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                        child: LoginHintCard(onLogin: widget.onLogin),
                      ),
                    // 拟物设备
                    Expanded(
                      flex: 28,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: PressMachine(
                          mode: _machineMode,
                          breath: _breath,
                          slotKey: _slotKey,
                          loadedTitle: _loadedItem?.title,
                        ),
                      ),
                    ),
                    // NFC 指引区
                    Expanded(
                      flex: 34,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        child: NfcGuidePanel(
                          phase: _guidePhase,
                          breath: _breath,
                          soundTitle: _loadedItem?.title,
                          progress: _pressProgress,
                          chaining: _chaining,
                          autoListening: _autoListening,
                          onStartDetect: () => _startNfcDetect(),
                          onCancelWrite: _cancelNfc,
                          onRetrieve: _retrieveSound,
                          onRetry: () => _startNfcDetect(),
                          onDetectOther: () => _startNfcDetect(),
                          onViewCollection: widget.onOpenCollection,
                          onContinue: _continueAfterComplete,
                          onStartRecord: widget.onStartRecord,
                        ),
                      ),
                    ),
                    // 卡片轮播
                    Expanded(
                      flex: 30,
                      child: AnimatedOpacity(
                        duration: AppMotion.fast,
                        opacity: (_flow != _FlowPhase.idle &&
                                _flow != _FlowPhase.complete)
                            ? 0.35
                            : 1,
                        child: tray.isEmpty
                            ? const SizedBox.shrink()
                            : DraftTrayCarousel(
                                items: tray,
                                selectedIndex: selected,
                                onIndexChanged: (i) =>
                                    setState(() => _selectedIndex = i),
                                onOpenDetail: (id) {
                                  if (_trayLocked) return;
                                  widget.onOpenDetail(id);
                                },
                                onLongPressCenter: _onLongPressCenter,
                                onLongPressMove: _onLongPressMove,
                                onLongPressEnd: _onLongPressEnd,
                                dimmed: dragging,
                                locked: _trayLocked,
                                placeholderIndex:
                                    (_dragPhase == _DragPhase.dragging ||
                                            _dragPhase == _DragPhase.snapping)
                                        ? _dragIndex
                                        : null,
                              ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
                if ((_dragPhase == _DragPhase.dragging ||
                        _dragPhase == _DragPhase.snapping ||
                        _dragPhase == _DragPhase.inserting ||
                        _dragPhase == _DragPhase.retrieving) &&
                    _dragGlobal != null &&
                    (_dragIndex != null ||
                        _dragPhase == _DragPhase.retrieving ||
                        _dragPhase == _DragPhase.inserting))
                  _DragLayer(
                    item: _dragIndex != null && _dragIndex! < tray.length
                        ? tray[_dragIndex!]
                        : (_loadedItem ??
                            (_dragIndex != null &&
                                    _dragIndex! < _allDrafts.length
                                ? _allDrafts[_dragIndex!]
                                : null)),
                    globalPosition: _dragGlobal!,
                    scale: _dragScale,
                    angle: _dragAngle,
                    insertProgress: _insertProgress,
                    stageGlobal: _stageRectGlobal(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CompactAccountButton extends StatelessWidget {
  const _CompactAccountButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.device,
          border: Border.all(color: AppColors.structure),
        ),
        child: Icon(icon, size: 16, color: AppColors.textTertiary),
      ),
    );
  }
}

class _DragLayer extends StatelessWidget {
  const _DragLayer({
    required this.item,
    required this.globalPosition,
    required this.scale,
    required this.angle,
    required this.insertProgress,
    required this.stageGlobal,
  });

  final SoundMemory? item;
  final Offset globalPosition;
  final double scale;
  final double angle;
  final double insertProgress;
  final Rect? stageGlobal;

  @override
  Widget build(BuildContext context) {
    if (item == null) return const SizedBox.shrink();
    final origin = stageGlobal?.topLeft ?? Offset.zero;
    final local = globalPosition - origin;
    const cardH = 248.0;
    final clipTop = insertProgress * cardH;

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: local.dx - 94,
              top: local.dy - 124,
              child: Transform.rotate(
                angle: angle,
                child: Transform.scale(
                  scale: scale,
                  child: ClipRect(
                    clipper: _BottomRevealClipper(hiddenTop: clipTop),
                    child: Opacity(
                      opacity: (1 - insertProgress * 0.15).clamp(0.55, 1),
                      child: DraftTrayCard(
                        item: item!,
                        elevated: true,
                        onTap: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 从顶部逐渐裁掉，模拟卡片下半部先进入插槽后被外壳遮挡。
class _BottomRevealClipper extends CustomClipper<Rect> {
  _BottomRevealClipper({required this.hiddenTop});

  final double hiddenTop;

  @override
  Rect getClip(Size size) {
    final top = hiddenTop.clamp(0.0, size.height);
    return Rect.fromLTRB(0, top, size.width, size.height);
  }

  @override
  bool shouldReclip(covariant _BottomRevealClipper old) =>
      old.hiddenTop != hiddenTop;
}

class DraftDetailScreen extends StatefulWidget {
  const DraftDetailScreen({
    super.key,
    required this.id,
    required this.onBack,
    required this.onDeleted,
  });

  final String id;
  final VoidCallback onBack;
  final VoidCallback onDeleted;

  @override
  State<DraftDetailScreen> createState() => _DraftDetailScreenState();
}

class _DraftDetailScreenState extends State<DraftDetailScreen> {
  bool _playing = false;
  bool _editing = false;
  final _player = AudioPlaybackService.instance;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  String? _category;

  @override
  void initState() {
    super.initState();
    final item = SoundRepository.instance.get(widget.id);
    _titleCtrl = TextEditingController(text: item?.title ?? '');
    _descCtrl = TextEditingController(text: item?.description ?? '');
    _category = item?.category;
  }

  @override
  void dispose() {
    _player.stop();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(String? path) async {
    if (path == null || path.isEmpty) {
      setState(() => _playing = !_playing);
      return;
    }
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
    } else {
      await _player.play(path);
      setState(() => _playing = true);
    }
  }

  Future<void> _pickCategory() async {
    final picked = await SpCategoryPicker.show(
      context,
      current: _category,
    );
    if (picked != null) setState(() => _category = picked);
  }

  void _saveEdit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称与分类不能为空')),
      );
      return;
    }
    SoundRepository.instance.update(
      widget.id,
      (s) => s.copyWith(
        title: title,
        category: _category,
        description: _descCtrl.text.trim(),
      ),
    );
    setState(() => _editing = false);
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这段声音？'),
        content: const Text('录音、声音视觉和相关记忆信息将被永久移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '确认删除',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (SoundRepository.instance.delete(widget.id)) {
        widget.onDeleted();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NFC 已写入的声音不可删除')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SoundRepository.instance,
      builder: (context, _) {
        final item = SoundRepository.instance.get(widget.id);
        if (item == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Drafts')),
            body: const Center(child: Text('声音不存在')),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          appBar: AppBar(
            title: const Text('暂存详情'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: widget.onBack,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (_editing) {
                    _saveEdit();
                  } else {
                    setState(() => _editing = true);
                  }
                },
                child: Text(
                  _editing ? '保存' : '编辑',
                  style: const TextStyle(color: AppColors.accent),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageHorizontal,
              ),
              children: [
                GestureDetector(
                  onTap: () => _togglePlay(item.audioPath),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(AppRadii.collectionCard),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ColoredBox(
                        color: AppColors.surface1,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SoundVisualCanvas(
                              seed: item.visualSeed,
                              mode: _playing
                                  ? SoundVisualMode.playback
                                  : SoundVisualMode.complete,
                            ),
                            Icon(
                              _playing
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                              size: 44,
                              color: AppColors.accent.withValues(alpha: 0.85),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.item),
                if (_editing) ...[
                  SpTextField(
                    controller: _titleCtrl,
                    label: '声音名称',
                    maxLength: 20,
                  ),
                  const SizedBox(height: AppSpacing.item),
                  const SectionLabel('分类'),
                  GestureDetector(
                    onTap: _pickCategory,
                    child: Container(
                      height: AppSizes.inputHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: AppColors.surface1,
                        borderRadius: BorderRadius.circular(AppRadii.input),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        _category ?? '选择分类',
                        style: TextStyle(
                          color: _category == null
                              ? AppColors.textTertiary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.item),
                  SpTextField(
                    controller: _descCtrl,
                    label: '描述（选填）',
                    maxLines: 3,
                    maxLength: 200,
                  ),
                ] else ...[
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '#${item.category} · ${formatDuration(item.durationSec)}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      StatusChip(status: item.status),
                      const SizedBox(width: 8),
                      RarityChip(
                        rarity: item.discRarity,
                        pending: item.rarityPending,
                      ),
                    ],
                  ),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.item),
                    Text(
                      item.description,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.item),
                  MetaRow(
                    label: '录制时间',
                    value: formatRecordedAt(item.recordedAt),
                  ),
                  MetaRow(label: '地点', value: item.locationLabel),
                  MetaRow(
                    label: '时长',
                    value: formatDuration(item.durationSec),
                  ),
                  MetaRow(label: '设备', value: item.deviceLabel),
                  MetaRow(
                    label: '声片稀有度',
                    value: item.rarityDisplayLabel,
                  ),
                  if (item.discId != null)
                    MetaRow(label: '声片编号', value: item.discId!),
                ],
                const SizedBox(height: AppSpacing.block),
                PrimaryButton(
                  text: '返回暂存台写入',
                  onPressed: widget.onBack,
                ),
                const SizedBox(height: AppSpacing.tight),
                const Text(
                  '请在 Drafts 页将卡片拖入设备，完成 NFC 封存。',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: AppSpacing.item),
                SecondaryButton(
                  text: '删除声音',
                  danger: true,
                  onPressed: _confirmDelete,
                ),
                const SizedBox(height: AppSpacing.section),
              ],
            ),
          ),
        );
      },
    );
  }
}
