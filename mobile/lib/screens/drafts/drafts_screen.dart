import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../cloud/cloud_media_client.dart';
import '../../cloud/cloud_media_config.dart';
import '../../cloud/cloud_media_models.dart';
import '../../cloud/cloud_upload.dart';
import '../../data/bay_disc_store.dart';
import '../../data/disc_rarity.dart';
import '../../data/session.dart';
import '../../data/sound_repository.dart';
import '../../router/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/audio_playback_service.dart';
import '../../services/chain_service.dart';
import '../../services/nfc_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/indexed_visual_player.dart';
import '../../widgets/sound_visual.dart';
import '../../widgets/sp_category_picker.dart';
import '../../visual/audio_feature_timeline.dart';
import '../../visual/visual_bake_service.dart';
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

enum _NfcWriteOutcome { success, alreadyBound }

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
  /// 仓内圆形声片：NFC 写入成功后落入，保留至多 7 天／5 张。
  List<BayStoredDisc> _bayDiscs = const [];
  String? _pressStatus;
  /// 失败是否发生在云端准备（无需 NFC）阶段。
  bool _failWasCloud = false;
  /// 第二次贴近后，正在向声片写 NDEF。
  bool _nfcWriting = false;
  bool _autoListening = false;
  bool _chaining = false;
  bool _nfcBusy = false;
  String? _failReason;

  late final AnimationController _breath;
  final GlobalKey _slotKey = GlobalKey();
  final GlobalKey _stageKey = GlobalKey();
  final CloudMediaClient _cloud = CloudMediaClient();

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    AuthService.instance.addListener(_onAuthChanged);
    _loadBayDiscs();
  }

  String? get _bayOwnerId => AuthService.instance.currentUser?.userId;

  void _onAuthChanged() {
    _loadBayDiscs();
  }

  Future<void> _loadBayDiscs() async {
    final discs = await BayDiscStore.instance.load(userId: _bayOwnerId);
    if (!mounted) return;
    setState(() => _bayDiscs = discs);
  }

  Future<void> _recordBayDrop(SoundMemory item) async {
    final discs = await BayDiscStore.instance.addDrop(
      userId: _bayOwnerId,
      id: item.id,
      visualSeed: item.visualSeed,
      rarity: item.discRarity,
    );
    if (!mounted) return;
    setState(() => _bayDiscs = discs);
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    NfcService.instance.stopSession();
    _cloud.close();
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
      _FlowPhase.idle => NfcGuidePhase.howto, // 仅作折叠提示，布局中不展开面板
      _FlowPhase.waitingNfc =>
        _autoListening ? NfcGuidePhase.checking : NfcGuidePhase.checkPrompt,
      // 云端上传／处理：明确引导「无需贴近」
      _FlowPhase.found => _cloudGuidePhase,
      _FlowPhase.pressing => _chaining
          ? NfcGuidePhase.chaining
          : (_nfcWriting
              ? NfcGuidePhase.writing
              : NfcGuidePhase.writePrompt),
      _FlowPhase.complete => NfcGuidePhase.complete,
      _FlowPhase.interrupted =>
        _failWasCloud ? NfcGuidePhase.cloudFailed : NfcGuidePhase.writeFailed,
      _FlowPhase.alreadyBound => NfcGuidePhase.cardAlreadyBound,
    };
  }

  NfcGuidePhase get _cloudGuidePhase {
    final s = _pressStatus ?? '';
    if (s.contains('上传')) return NfcGuidePhase.cloudUploading;
    return NfcGuidePhase.cloudProcessing;
  }

  CloudPrepStage get _cloudStage {
    final s = _pressStatus ?? '';
    if (s.contains('上传')) return CloudPrepStage.upload;
    if (s.contains('再次贴近') || s.contains('已就绪') || s.contains('拿到')) {
      return CloudPrepStage.ready;
    }
    return CloudPrepStage.process;
  }

  bool get _isSelecting =>
      _flow == _FlowPhase.idle &&
      _dragPhase != _DragPhase.inserting &&
      _dragPhase != _DragPhase.retrieving;

  /// NFC 面板：仅插入后，或空队列引导。
  bool get _showNfcPanel =>
      _flow != _FlowPhase.idle || _allDrafts.isEmpty;

  bool get _showCarousel =>
      _isSelecting &&
      _trayItems.isNotEmpty &&
      (_dragPhase == _DragPhase.idle ||
          _dragPhase == _DragPhase.dragging ||
          _dragPhase == _DragPhase.snapping);

  bool _canPress(SoundMemory item) =>
      item.status == SoundStatus.drafted ||
      item.status == SoundStatus.cloudReady ||
      item.status == SoundStatus.writeFailed ||
      item.status == SoundStatus.chainFailed;

  bool _isCloudPayloadReady(SoundMemory item) {
    final cid = item.contentId?.trim() ?? '';
    if (cid.isEmpty) return false;
    return (item.cloudState ?? '').toUpperCase() == 'READY';
  }

  Rect? _slotHitRectGlobal() {
    final box = _slotKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    // Expanded affinity zone — top slot; approach from below then drop in.
    return Rect.fromLTWH(
      topLeft.dx - 48,
      topLeft.dy - 100,
      box.size.width + 96,
      box.size.height + 150,
    );
  }

  /// Exact slot bounds — used for insert path + occlusion clip.
  Rect? _slotMouthRectGlobal() {
    final box = _slotKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
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
    final slot = _slotHitRectGlobal();
    var mode = PressMachineMode.receiving;
    var scale = 1.04;
    var angle = 0.0;
    var near = false;

    if (slot != null) {
      final dist = (next - slot.center).distance;
      angle = ui.lerpDouble(_dragAngle, 0.02, ((1 - dist / 280).clamp(0.0, 1.0)) * 0.5)!;
      if (slot.contains(next) || dist < 95) {
        mode = PressMachineMode.readyToRelease;
        near = true;
        angle = 0;
      }
      // Keep card size constant — insert uses path + occlusion, not shrink.
      scale = 1.04;
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
    final slot = _slotHitRectGlobal();
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

  /// 吸附到顶部插口上方 → 停顿 → 下吸入槽（口下被机身遮挡）→ 消失。
  Future<void> _runInsertAnimation() async {
    final items = _trayItems;
    final index = _dragIndex;
    final mouth = _slotMouthRectGlobal();
    if (index == null || index >= items.length || mouth == null) {
      await _springBack();
      return;
    }
    final item = items[index];
    const cardH = _DragLayer.cardH;

    HapticFeedback.mediumImpact();

    // 1) Snap: card hangs mostly above the upward-facing slot.
    final snapY = mouth.top - cardH * 0.28;
    setState(() {
      _dragPhase = _DragPhase.snapping;
      _dragGlobal = Offset(mouth.center.dx, snapY);
      _dragScale = 1.0;
      _dragAngle = 0;
      _insertProgress = 0;
      _machineMode = PressMachineMode.readyToRelease;
    });
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!mounted) return;

    // 2) Slide down into slot — occlude below mouth; keep size (no shrink).
    setState(() {
      _dragPhase = _DragPhase.inserting;
      _machineMode = PressMachineMode.inserting;
      _dragScale = 1.0;
    });

    final endY = mouth.bottom + cardH * 0.42;
    const steps = 10;
    for (var i = 1; i <= steps; i++) {
      if (!mounted) return;
      final t = i / steps;
      final eased = Curves.easeInCubic.transform(t);
      setState(() {
        _insertProgress = eased;
        _dragGlobal = Offset(
          mouth.center.dx,
          ui.lerpDouble(snapY, endY, eased)!,
        );
        _dragScale = 1.0;
      });
      await Future<void>.delayed(const Duration(milliseconds: 48));
    }
    if (!mounted) return;

    setState(() {
      _dragPhase = _DragPhase.idle;
      _dragIndex = null;
      _dragGlobal = null;
      _insertProgress = 1;
      _loadedId = item.id;
      _loadedItem = item;
      _flow = _FlowPhase.waitingNfc;
      _machineMode = PressMachineMode.loaded;
    });
    HapticFeedback.selectionClick();

    if (!AuthService.instance.isLoggedIn) {
      widget.onLogin();
    }
  }

  Future<void> _retrieveSound() async {
    if (_flow == _FlowPhase.pressing || _flow == _FlowPhase.found) return;
    if (_loadedItem == null) return;

    await NfcService.instance.stopSession();
    _autoListening = false;

    final mouth = _slotMouthRectGlobal();
    final item = _loadedItem!;
    const cardH = _DragLayer.cardH;

    setState(() {
      _dragPhase = _DragPhase.retrieving;
      _machineMode = PressMachineMode.receiving;
      _flow = _FlowPhase.idle;
      _nfcWriting = false;
      _failWasCloud = false;
      _dragGlobal = mouth != null
          ? Offset(mouth.center.dx, mouth.bottom + cardH * 0.35)
          : Offset.zero;
      _dragScale = 1.0;
      _insertProgress = 0.9;
      _dragIndex = null;
      _loadedId = null;
      _loadedItem = item;
    });

    if (mouth != null) {
      // Eject upward out of the top slot.
      final startY = mouth.bottom + cardH * 0.35;
      final endY = mouth.top - cardH * 0.28;
      for (var i = 1; i <= 8; i++) {
        if (!mounted) return;
        final t = i / 8;
        final eased = Curves.easeOutCubic.transform(t);
        setState(() {
          _insertProgress = ui.lerpDouble(0.9, 0, eased)!;
          _dragGlobal = Offset(
            mouth.center.dx,
            ui.lerpDouble(startY, endY, eased)!,
          );
          _dragScale = 1.0;
        });
        await Future<void>.delayed(const Duration(milliseconds: 42));
      }
    }

    if (!mounted) return;
    setState(() {
      _dragPhase = _DragPhase.idle;
      _dragGlobal = null;
      _insertProgress = 0;
      _loadedId = null;
      _loadedItem = null;
      final idx = _trayItems.indexWhere((s) => s.id == item.id);
      if (idx >= 0) _selectedIndex = idx;
      _syncMachineIdle();
    });
  }

  // ─── NFC ────────────────────────────────────────────

  Future<void> _failPress(String reason, {bool cloud = false}) async {
    await NfcService.instance.stopSession(error: reason);
    _nfcBusy = false;
    if (!mounted) return;
    setState(() {
      _failReason = reason;
      _pressStatus = null;
      _flow = _FlowPhase.interrupted;
      _machineMode = PressMachineMode.interrupted;
      _autoListening = false;
      _nfcWriting = false;
      _failWasCloud = cloud;
    });
  }

  /// 单次流程：云端准备（无需 NFC）→ 一次贴近完成检查＋写入。
  Future<void> _startPressFlow() async {
    if (_loadedItem == null) return;
    if (_nfcBusy) {
      await NfcService.instance.stopSession();
      _nfcBusy = false;
    }
    if (!AuthService.instance.isLoggedIn) {
      widget.onLogin();
      return;
    }

    final status = await NfcService.instance.checkStatus();
    if (status != NfcDeviceStatus.available) {
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

    await _prepareCloudAndWrite();
  }

  /// 从仓库刷新当前插入声音，避免 contentId／nfcUrl 仍用旧快照。
  SoundMemory? _freshLoadedItem() {
    final id = _loadedId ?? _loadedItem?.id;
    if (id == null) return _loadedItem;
    final fresh = SoundRepository.instance.get(id);
    if (fresh != null) _loadedItem = fresh;
    return _loadedItem;
  }

  bool _hasCloudWritePayload(SoundMemory item) {
    final cid = item.contentId?.trim() ?? '';
    final url = item.nfcUrl?.trim() ?? '';
    return cid.isNotEmpty || url.isNotEmpty;
  }

  String _writeUrlFor(SoundMemory item, {String? contentId, String? nfcUrl}) {
    final url = (nfcUrl ?? item.nfcUrl)?.trim();
    if (url != null && url.isNotEmpty) return url;
    final cid = (contentId ?? item.contentId)?.trim() ?? '';
    return '${CloudMediaConfig.baseUrl}/c/$cid';
  }

  /// 云端就绪 → 单次 NFC：检查是否已写入，空白则写入。
  Future<void> _prepareCloudAndWrite() async {
    final item = _freshLoadedItem();
    if (item == null) {
      await _failPress('写入会话丢失，请重新插入声音。');
      return;
    }

    // 录音后已预上传且 READY：跳过上传／生成，直接写入。
    if (_isCloudPayloadReady(item)) {
      final contentId = item.contentId!.trim();
      final writeUrl = _writeUrlFor(item);
      await _beginNfcWriteSession(
        item: item,
        contentId: contentId,
        writeUrl: writeUrl,
        cloudState: item.cloudState ?? 'READY',
      );
      return;
    }

    setState(() {
      _flow = _FlowPhase.found;
      _machineMode = PressMachineMode.preparing;
      _pressStatus = '正在连接云端…';
      _autoListening = false;
      _nfcWriting = false;
      _failReason = null;
      _failWasCloud = false;
    });

    ContentSummary ready;
    try {
      final token = await AuthService.instance.requireCloudToken();
      await _cloud.assertReachable();
      ready = await _ensureCloudReady(item, token);
    } catch (e) {
      await _failPress(_friendlyCloudError(e), cloud: true);
      return;
    }

    final nfcUrl = ready.nfcUrl?.trim();
    final contentId = ready.contentId.trim();
    if (contentId.isEmpty && (nfcUrl == null || nfcUrl.isEmpty)) {
      await _failPress('云端未返回可写入链接，请稍后重试。', cloud: true);
      return;
    }
    final writeUrl = _writeUrlFor(item, contentId: contentId, nfcUrl: nfcUrl);

    if (!mounted) return;
    if (_flow != _FlowPhase.found && _flow != _FlowPhase.pressing) return;

    SoundRepository.instance.update(
      item.id,
      (s) => s.copyWith(
        contentId: contentId,
        nfcUrl: writeUrl,
        cloudState: ready.state.wire,
        status: SoundStatus.writing,
      ),
    );
    _freshLoadedItem();

    await _beginNfcWriteSession(
      item: _loadedItem ?? item,
      contentId: contentId,
      writeUrl: writeUrl,
      cloudState: ready.state.wire,
    );
  }

  /// 已绑定冲突后换空白声片：云端内容已就绪则跳过上传／生成，直接进入写入。
  Future<void> _resumeWriteOnBlankCard() async {
    if (_nfcBusy) {
      await NfcService.instance.stopSession();
      _nfcBusy = false;
    }
    final item = _freshLoadedItem();
    if (item == null) {
      await _failPress('写入会话丢失，请重新插入声音。');
      return;
    }
    if (!_hasCloudWritePayload(item)) {
      await _prepareCloudAndWrite();
      return;
    }

    final contentId = item.contentId?.trim() ?? '';
    final writeUrl = _writeUrlFor(item);
    await _beginNfcWriteSession(
      item: item,
      contentId: contentId.isNotEmpty ? contentId : writeUrl,
      writeUrl: writeUrl,
      cloudState: item.cloudState ?? 'READY',
    );
  }

  /// 仅 NFC：贴近检查并写入（不触碰云端上传／生成）。
  Future<void> _beginNfcWriteSession({
    required SoundMemory item,
    required String contentId,
    required String writeUrl,
    String? cloudState,
  }) async {
    if (!mounted) return;
    setState(() {
      _flow = _FlowPhase.pressing;
      _machineMode = PressMachineMode.readyToWrite;
      _pressStatus = '请贴近空白声片，检查并写入…';
      _autoListening = true;
      _nfcWriting = false;
      _failReason = null;
      _failWasCloud = false;
    });

    _nfcBusy = true;
    final completer = Completer<_NfcWriteOutcome>();

    try {
      await NfcService.instance.startSession(
        alertMessage: '请将空白声片贴近手机背面，完成检查与写入',
        invalidateAfterFirstRead: false,
        onDiscovered: (tag) async {
          if (completer.isCompleted) return;
          try {
            final binding = await NfcService.instance.readBinding(tag);
            if (binding != null) {
              await NfcService.instance.stopSession(message: '该声片已绑定');
              if (!completer.isCompleted) {
                completer.complete(_NfcWriteOutcome.alreadyBound);
              }
              return;
            }

            final writable = await NfcService.instance.canWriteTag(tag);
            if (!writable) {
              throw StateError('声片不可写入，或不是空白 SoundPola 声片。请换一枚未绑定声片。');
            }

            final factoryProfile =
                await NfcService.instance.readFactoryProfile(tag);
            if (factoryProfile == null) {
              throw StateError('未识别到声片出厂信息。');
            }
            if (factoryProfile.bound) {
              await NfcService.instance.stopSession(message: '该声片已绑定');
              if (!completer.isCompleted) {
                completer.complete(_NfcWriteOutcome.alreadyBound);
              }
              return;
            }

            PressSession.set(
              tagId: NfcService.instance.tagIdHex(tag),
              disc: factoryProfile.discId,
              discRarity: factoryProfile.rarity,
              discSeries: factoryProfile.series,
              signature: factoryProfile.signature,
              demo: factoryProfile.demo,
            );

            if (mounted) {
              setState(() {
                _nfcWriting = true;
                _pressStatus = '正在写入声片…';
              });
            }

            final factory = factoryProfile.copyWith(bound: true);

            Future<void> doWrite() => NfcService.instance.writeBinding(
                  tag: tag,
                  soundId: item.id,
                  discId: factory.discId,
                  title: item.title,
                  contentId: contentId,
                  nfcUrl: writeUrl,
                  rarity: factory.rarity,
                  series: factory.series,
                  factory: factory,
                );

            try {
              await doWrite();
            } catch (e) {
              final blob = e.toString().toLowerCase();
              if (blob.contains('ioexception') || blob.contains('tag')) {
                await Future<void>.delayed(const Duration(milliseconds: 120));
                await doWrite();
              } else {
                rethrow;
              }
            }
            await NfcService.instance.stopSession(message: '写入成功');
            if (!completer.isCompleted) {
              completer.complete(_NfcWriteOutcome.success);
            }
          } catch (e) {
            await NfcService.instance.stopSession(error: '写入失败');
            if (!completer.isCompleted) completer.completeError(e);
          }
        },
      );

      final outcome =
          await completer.future.timeout(const Duration(seconds: 40));
      _nfcBusy = false;
      if (!mounted) return;

      if (outcome == _NfcWriteOutcome.alreadyBound) {
        HapticFeedback.mediumImpact();
        setState(() {
          _flow = _FlowPhase.alreadyBound;
          _machineMode = PressMachineMode.alreadyBound;
          _autoListening = false;
          _nfcWriting = false;
          _pressStatus = null;
          _failReason = null;
        });
        return;
      }
    } on TimeoutException {
      await _failPress('写入超时。请保持声片贴近 NFC 区域后重试。');
      return;
    } catch (e) {
      await _failPress(_friendlyNfcError(e));
      return;
    }

    final discId = PressSession.discId;
    final rarity = PressSession.rarity;
    if (discId == null || rarity == null) {
      await _failPress('声片信息丢失，请重试。');
      return;
    }

    setState(() {
      _pressStatus = '正在上链…';
      _autoListening = false;
      _nfcWriting = false;
      _chaining = true;
    });
    await _recordBayDrop(item);

    final assetId = await ChainService.instance.submitAsset(
      soundId: item.id,
      discId: discId,
      rarityCode: rarity.code,
      series: PressSession.series,
    );

    if (!mounted) return;

    SoundRepository.instance.markCollected(
      item.id,
      discId,
      assetId,
      nfcTagId: PressSession.tagIdHex,
      contentId: contentId,
      nfcUrl: writeUrl,
      cloudState: cloudState,
      discRarity: rarity,
      discSeries: PressSession.series,
    );

    PressSession.clear();
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() {
      _flow = _FlowPhase.complete;
      _machineMode = PressMachineMode.complete;
      _chaining = true;
      _loadedId = null;
      _pressStatus = null;
      _failReason = null;
    });
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _chaining = false);
    });
  }

  /// 云端失败 → 重走准备；NFC 写入失败 / 换空白片 → 直接写入（不重复上传）。
  Future<void> _retryAfterFail() async {
    if (_freshLoadedItem() == null) return;
    if (_failWasCloud) {
      await _prepareCloudAndWrite();
      return;
    }
    await _resumeWriteOnBlankCard();
  }

  Future<ContentSummary> _ensureCloudReady(
    SoundMemory item,
    String token,
  ) async {
    var contentId = item.contentId;

    if (contentId != null && contentId.isNotEmpty) {
      var summary = await _cloud.getContent(token: token, contentId: contentId);
      if (summary.state == CloudContentState.ready) {
        if (mounted) {
          setState(() {
            _pressStatus = '云端链接已就绪';
          });
        }
        return summary;
      }
      if (summary.state == CloudContentState.failed) {
        if (mounted) {
          setState(() {
            _pressStatus = '云端处理失败，正在重试…';
          });
        }
        summary = await _cloud.retryContent(token: token, contentId: contentId);
      }
      if (summary.state == CloudContentState.ready) return summary;
      if (mounted) {
        setState(() {
          _pressStatus = '云端处理中…';
        });
      }
      final baked =
          await VisualBakeService.instance.ensureReady(item.id) ?? item;
      final video = await attachVisualVideoIfNeeded(
        cloud: _cloud,
        item: baked,
        token: token,
        contentId: contentId,
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _pressStatus = status);
        },
      );
      if (video != null && video.state == CloudContentState.ready) {
        return _cloud.getContent(token: token, contentId: contentId);
      }
      return _cloud.waitUntilReady(
        token: token,
        contentId: contentId,
        onUpdate: (s) {
          if (!mounted) return;
          setState(() {
            _pressStatus = '云端处理：${s.state.wire}';
          });
        },
      );
    }

    final path = item.audioPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      throw StateError('缺少本地录音文件，无法上传云端');
    }

    if (mounted) {
      setState(() {
        _pressStatus = '正在准备可视化帧序列…';
      });
    }
    final created = await uploadSoundPackage(
      cloud: _cloud,
      item: item,
      token: token,
      onStatus: (status) {
        if (!mounted) return;
        setState(() => _pressStatus = status);
      },
    );
    contentId = created.contentId;
    SoundRepository.instance.update(
      item.id,
      (s) => s.copyWith(contentId: contentId, cloudState: created.state.wire),
    );
    if (_loadedId == item.id || _loadedItem?.id == item.id) {
      _freshLoadedItem();
    }

    if (mounted) {
      setState(() {
        _pressStatus = '云端处理中…';
      });
    }
    return _cloud.waitUntilReady(
      token: token,
      contentId: contentId,
      onUpdate: (s) {
        if (!mounted) return;
        setState(() {
          _pressStatus = '云端处理：${s.state.wire}';
        });
      },
    );
  }

  String _friendlyCloudError(Object e) {
    if (e is CloudMediaException) {
      final msg = e.message.trim();
      if (msg.isEmpty) return '云端服务异常，请稍后重试。';
      if (msg.length > 100) return '${msg.substring(0, 100)}…';
      return msg;
    }
    if (e is StateError) {
      return e.message;
    }
    final blob = e.toString().toLowerCase();
    if (blob.contains('socket') ||
        blob.contains('network') ||
        blob.contains('failed host') ||
        blob.contains('connection')) {
      return '网络不可用，无法上传云端。请检查网络后重试。';
    }
    if (blob.contains('token') || blob.contains('401') || blob.contains('403')) {
      return '云端登录已失效，请重新登录后再写入。';
    }
    return '云端准备失败，请稍后重试。';
  }

  String _friendlyNfcError(Object e) {
    String code = '';
    String message = '';
    if (e is PlatformException) {
      code = e.code;
      message = e.message ?? e.details?.toString() ?? '';
    } else if (e is TimeoutException) {
      return '写入超时。请保持声片贴近 NFC 区域后重试。';
    } else if (e is StateError) {
      message = e.message;
    } else {
      message = e.toString();
    }

    // 去掉堆栈，只留首行/短消息
    message = message
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => message)
        .trim();
    if (message.length > 120) {
      message = '${message.substring(0, 120)}…';
    }

    final blob = '$code $message'.toLowerCase();
    if (blob.contains('already') || message.contains('已绑定')) {
      return '这枚声片已经封存过声音，请更换未绑定声片。';
    }
    if (blob.contains('防伪') || blob.contains('authentic')) {
      return '声片防伪校验失败，请使用正版声片。';
    }
    if (blob.contains('不可写入') || blob.contains('not writable')) {
      return '声片当前不可写入，请确认是空白 SoundPola 声片。';
    }
    if (blob.contains('ioexception') ||
        blob.contains('tag was lost') ||
        blob.contains('tag is out') ||
        (blob.contains('ndef') && blob.contains('fail')) ||
        code == 'IOException') {
      return '写入时声片连接中断。请紧贴手机背面保持不动，然后点「重新检测」。';
    }
    if (blob.contains('timeout') || blob.contains('超时')) {
      return '写入超时。请保持声片贴近后重试。';
    }
    if (blob.contains('session') || blob.contains('会话')) {
      return 'NFC 会话已结束，请重新检测声片。';
    }
    // 默认：绝不把堆栈甩到 UI
    return '写入未完成。请保持声片贴近手机背面后重试。';
  }

  Future<void> _simulatePress() async {
    final item = _loadedItem;
    if (item == null) return;
    await NfcService.instance.stopSession();
    _nfcBusy = false;
    HapticFeedback.mediumImpact();
    setState(() {
      _failReason = null;
      _flow = _FlowPhase.found;
      _machineMode = PressMachineMode.preparing;
      _pressStatus = '模拟：准备云端链接…';
    });
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;

    setState(() {
      _flow = _FlowPhase.pressing;
      _machineMode = PressMachineMode.writing;
      _pressStatus = '模拟：上传并获取链接…';
    });

    String? contentId = item.contentId;
    String? nfcUrl = item.nfcUrl;
    try {
      final token = await AuthService.instance.requireCloudToken();
      await _cloud.assertReachable();
      final ready = await _ensureCloudReady(item, token);
      contentId = ready.contentId;
      nfcUrl = ready.nfcUrl;
      if (mounted) {
        setState(() {
          _pressStatus = '模拟：已拿到云端链接（跳过真机 NFC）';
        });
      }
    } catch (_) {
      // 调试机允许无网络完成流程
      if (mounted) {
        setState(() {
          _pressStatus = '模拟写入（未连云端）';
        });
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    // 模拟写入成功 → 声片落入毛玻璃仓。
    await _recordBayDrop(item);

    final discId = NfcService.instance.generateDiscId('DEMO');
    final rarity = DiscRarity.rollWeighted();
    final assetId = await ChainService.instance.submitAsset(
      soundId: item.id,
      discId: discId,
      rarityCode: rarity.code,
      series: 'Genesis-Sim',
    );
    SoundRepository.instance.markCollected(
      item.id,
      discId,
      assetId,
      contentId: contentId,
      nfcUrl: nfcUrl,
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
      _pressStatus = null;
      _failReason = null;
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
      _nfcWriting = false;
      _pressStatus = null;
      if (_flow == _FlowPhase.pressing || _flow == _FlowPhase.found) {
        _flow = _FlowPhase.waitingNfc;
        _machineMode = PressMachineMode.loaded;
      } else {
        _flow = _FlowPhase.waitingNfc;
        _machineMode = PressMachineMode.loaded;
      }
    });
  }

  void _continueAfterComplete() {
    setState(() {
      _flow = _FlowPhase.idle;
      _loadedItem = null;
      _loadedId = null;
      _pressStatus = null;
      _chaining = false;
      _nfcWriting = false;
      _failWasCloud = false;
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
        final screenH = MediaQuery.sizeOf(context).height;
        final machineMaxH = (screenH * 0.38).clamp(210.0, 280.0);

        return ColoredBox(
          color: const Color(0xFF030505),
          child: SafeArea(
            bottom: false,
            child: Stack(
              key: _stageKey,
              clipBehavior: Clip.none,
              children: [
                const Positioned.fill(child: _WorkbenchBackdrop()),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 标题
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 16, 2),
                      child: AnimatedOpacity(
                        duration: AppMotion.fast,
                        opacity: dragging ? 0.35 : 1,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Drafts',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 34,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.7,
                                      height: 1.05,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    '待封存的声音',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Text(
                                countLabel,
                                style: const TextStyle(
                                  fontFamily: 'Courier',
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (!loggedIn)
                              _FrostAccountButton(onTap: widget.onLogin)
                            else
                              const AccountAvatarButton(compact: true),
                          ],
                        ),
                      ),
                    ),
                    if (!loggedIn && _isSelecting)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: LoginHintCard(onLogin: widget.onLogin),
                      ),

                    // 写入设备（动态高度，不抢满屏）
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: SizedBox(
                        height: machineMaxH + 8,
                        child: PressMachine(
                          mode: _machineMode,
                          breath: _breath,
                          slotKey: _slotKey,
                          loadedTitle: _loadedItem?.title,
                          storedDiscs: _bayDiscs,
                          maxHeight: machineMaxH,
                        ),
                      ),
                    ),

                    // Selecting：短提示；插入后 / 空队列：NFC 面板
                    if (_showNfcPanel)
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                          child: NfcGuidePanel(
                            phase: _allDrafts.isEmpty && _flow == _FlowPhase.idle
                                ? NfcGuidePhase.empty
                                : _guidePhase,
                            breath: _breath,
                            soundTitle: _loadedItem?.title,
                            cloudStage: (_flow == _FlowPhase.found ||
                                    _guidePhase ==
                                        NfcGuidePhase.cloudUploading ||
                                    _guidePhase ==
                                        NfcGuidePhase.cloudProcessing)
                                ? _cloudStage
                                : null,
                            statusHint: _pressStatus,
                            chaining: _chaining,
                            failReason: _failReason,
                            autoListening: _autoListening,
                            onStartDetect: _startPressFlow,
                            onCancelWrite: _cancelNfc,
                            onRetrieve: _retrieveSound,
                            onRetry: _retryAfterFail,
                            onDetectOther: _resumeWriteOnBlankCard,
                            onViewCollection: widget.onOpenCollection,
                            onContinue: _continueAfterComplete,
                            onStartRecord: widget.onStartRecord,
                          ),
                        ),
                      )
                    else ...[
                      SizedBox(
                        height: 20,
                        child: Center(
                          child: AnimatedOpacity(
                            duration: AppMotion.fast,
                            opacity: dragging ? 0.9 : 0.4,
                            child: Container(
                              width: 1.2,
                              height: 14,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(1),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    AppColors.accent.withValues(alpha: 0.32),
                                    AppColors.accent.withValues(alpha: 0.02),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 0, 28, 6),
                        child: AnimatedOpacity(
                          duration: AppMotion.fast,
                          opacity: dragging ? 0.95 : 1,
                          child: Text(
                            dragging
                                ? (_machineMode ==
                                        PressMachineMode.readyToRelease
                                    ? '松开以插入顶部插口'
                                    : '向上拖至顶部插口封存')
                                : '点开声卡可发送至设备；或长按拖至顶部插口用手机 NFC 封存',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: dragging
                                  ? AppColors.accent
                                  : AppColors.textSecondary
                                      .withValues(alpha: 0.85),
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                      if (!dragging &&
                          !_trayLocked &&
                          tray.isNotEmpty &&
                          selected < tray.length)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 0, 28, 4),
                          child: Center(
                            child: TextButton(
                              onPressed: () => context.push(
                                AppRoutes.pressHardwarePath(tray[selected].id),
                              ),
                              child: const Text(
                                '发送至设备写入',
                                style: TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_showCarousel)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: DraftTrayCarousel(
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
                              spreadPeers: dragging,
                              locked: _trayLocked,
                              placeholderIndex:
                                  (_dragPhase == _DragPhase.dragging ||
                                          _dragPhase == _DragPhase.snapping)
                                      ? _dragIndex
                                      : null,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
                if ((_dragPhase == _DragPhase.dragging ||
                        _dragPhase == _DragPhase.snapping ||
                        _dragPhase == _DragPhase.inserting ||
                        _dragPhase == _DragPhase.retrieving) &&
                    _dragGlobal != null)
                  _DragLayer(
                    item: _dragIndex != null && _dragIndex! < tray.length
                        ? tray[_dragIndex!]
                        : _loadedItem,
                    globalPosition: _dragGlobal!,
                    scale: _dragScale,
                    angle: _dragAngle,
                    insertProgress: _insertProgress,
                    stageGlobal: _stageRectGlobal(),
                    slotMouthGlobal: _slotMouthRectGlobal(),
                    draftNumber: (_dragIndex ?? 0) + 1,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WorkbenchBackdrop extends StatelessWidget {
  const _WorkbenchBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _WorkbenchPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _WorkbenchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.38;
    final rect = Offset.zero & size;
    final radial = Paint()
      ..shader = ui.Gradient.radial(
        Offset(cx, cy),
        size.shortestSide * 0.85,
        [
          const Color(0xFF0A1614).withValues(alpha: 0.07),
          const Color(0xFF030505).withValues(alpha: 0),
        ],
      );
    canvas.drawRect(rect, radial);

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 0.6;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FrostAccountButton extends StatelessWidget {
  const _FrostAccountButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.28),
              ),
            ),
            child: Icon(
              Icons.person_outline,
              size: 17,
              color: AppColors.textPrimary.withValues(alpha: 0.9),
            ),
          ),
        ),
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
    this.slotMouthGlobal,
    this.draftNumber = 1,
  });

  final SoundMemory? item;
  final Offset globalPosition;
  final double scale;
  final double angle;
  final double insertProgress;
  final Rect? stageGlobal;
  /// Exact slot bounds in global coords — clip card below mouth (inside body).
  final Rect? slotMouthGlobal;
  final int draftNumber;

  static const cardW = 178.0;
  static const cardH = 232.0;

  @override
  Widget build(BuildContext context) {
    if (item == null) return const SizedBox.shrink();
    final origin = stageGlobal?.topLeft ?? Offset.zero;
    final local = globalPosition - origin;
    final cardTop = local.dy - cardH / 2;

    // Top slot: hide everything below the mouth (inside the machine body).
    double visibleBottom;
    final mouth = slotMouthGlobal;
    if (mouth != null && insertProgress > 0.001) {
      final mouthLocalY = mouth.top - origin.dy;
      visibleBottom = (mouthLocalY - cardTop).clamp(0.0, cardH);
    } else {
      visibleBottom = cardH;
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: local.dx - cardW / 2,
              top: cardTop,
              width: cardW,
              height: cardH,
              child: Transform.rotate(
                angle: angle,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.bottomCenter,
                  child: ClipRect(
                    clipper: _SlotOcclusionClipper(
                      visibleBottom: visibleBottom,
                    ),
                    child: Opacity(
                      opacity: (1 - insertProgress * 0.2).clamp(0.45, 1),
                      child: DraftTrayCard(
                        item: item!,
                        draftNumber: draftNumber,
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

/// Keep only the portion of the card still above the top slot mouth.
class _SlotOcclusionClipper extends CustomClipper<Rect> {
  _SlotOcclusionClipper({required this.visibleBottom});

  final double visibleBottom;

  @override
  Rect getClip(Size size) {
    final bottom = visibleBottom.clamp(0.0, size.height);
    return Rect.fromLTRB(0, 0, size.width, bottom);
  }

  @override
  bool shouldReclip(covariant _SlotOcclusionClipper old) =>
      old.visibleBottom != visibleBottom;
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
  final ValueNotifier<int> _positionMs = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    final item = SoundRepository.instance.get(widget.id);
    _titleCtrl = TextEditingController(text: item?.title ?? '');
    _descCtrl = TextEditingController(text: item?.description ?? '');
    _category = item?.category;
    _player.addListener(_onPlayer);
    SoundRepository.instance.addListener(_onRepo);
  }

  void _onRepo() {
    if (mounted) setState(() {});
  }

  void _onPlayer() {
    final item = SoundRepository.instance.get(widget.id);
    final path = item?.audioPath;
    if (path != null && _player.currentPath == path) {
      _positionMs.value = _player.position.inMilliseconds;
      final playing = _player.isPlaying;
      if (playing != _playing && mounted) {
        setState(() => _playing = playing);
      }
    }
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayer);
    SoundRepository.instance.removeListener(_onRepo);
    _player.stop();
    _positionMs.dispose();
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
                            if (item.hasIndexedVisual)
                              Positioned.fill(
                                child: IndexedVisualPlayer(
                                  item: item,
                                  positionMsListenable: _positionMs,
                                ),
                              )
                            else if (item.coverPath != null)
                              Positioned.fill(
                                child: Image.file(
                                  File(item.coverPath!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, e, st) =>
                                      SoundVisualCanvas(
                                    seed: item.visualSeed,
                                    mode: SoundVisualMode.complete,
                                  ),
                                ),
                              )
                            else
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
                if (item.visualBakeStatus == VisualBakeStatus.processingVisual ||
                    item.visualBakeStatus == VisualBakeStatus.indexing) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '正在生成可视化帧流…',
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  ),
                ],
                if (item.visualBakeStatus == VisualBakeStatus.failed) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        VisualBakeService.instance.retry(item.id),
                    child: const Text(
                      '重新生成可视化',
                      style: TextStyle(color: AppColors.accent),
                    ),
                  ),
                ],
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
                if (!_editing) ...[
                  PrimaryButton(
                    text: '发送至设备写入',
                    onPressed: () =>
                        context.push(AppRoutes.pressHardwarePath(widget.id)),
                  ),
                  const SizedBox(height: AppSpacing.tight),
                  const Text(
                    'APP 发送写入任务后，请在设备端放入空白 Sound Piece 完成写入与校验。',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.item),
                  SecondaryButton(
                    text: '编辑声音信息',
                    onPressed: () => setState(() => _editing = true),
                  ),
                  const SizedBox(height: AppSpacing.item),
                  SecondaryButton(
                    text: '删除',
                    danger: true,
                    onPressed: _confirmDelete,
                  ),
                ] else ...[
                  PrimaryButton(
                    text: '保存',
                    onPressed: _saveEdit,
                  ),
                  const SizedBox(height: AppSpacing.item),
                  SecondaryButton(
                    text: '取消编辑',
                    onPressed: () {
                      final item = SoundRepository.instance.get(widget.id);
                      setState(() {
                        _editing = false;
                        _titleCtrl.text = item?.title ?? '';
                        _descCtrl.text = item?.description ?? '';
                        _category = item?.category;
                      });
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.section),
              ],
            ),
          ),
        );
      },
    );
  }
}
