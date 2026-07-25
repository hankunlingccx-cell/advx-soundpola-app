import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/sound_repository.dart';
import '../../services/audio_playback_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/empty_state_panel.dart';
import '../../widgets/sound_visual.dart';
import 'draft_tray_carousel.dart';
import 'press_machine.dart';

const _kGuideSeenKey = 'drafts_press_guide_seen_v1';

enum _DragPhase { idle, dragging, snapping, inserting }

class DraftsScreen extends StatefulWidget {
  const DraftsScreen({
    super.key,
    required this.onOpenDetail,
    required this.onPress,
    required this.onStartRecord,
    required this.onOpenCollection,
    required this.onLogin,
  });

  final ValueChanged<String> onOpenDetail;
  final ValueChanged<String> onPress;
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
  Offset? _dragGlobal;
  int? _dragIndex;
  double _dragScale = 1;
  double _dragAngle = 0;
  bool _trayLocked = false;
  bool _showGuideHint = false;
  double _guideFlash = 0;
  String? _pendingPressId;
  SoundMemory? _completeCard;

  late final AnimationController _breath;
  late final AnimationController _guide;
  final GlobalKey _slotKey = GlobalKey();
  final GlobalKey _stageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _guide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _guide.addListener(() {
      // 0–0.35 浮起扫描，之后淡出
      final t = _guide.value;
      setState(() {
        if (t < 0.4) {
          _guideFlash = math.sin(t / 0.4 * math.pi);
        } else {
          _guideFlash = 0;
        }
      });
    });
    _guide.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _showGuideHint = false);
      }
    });
    SoundRepository.instance.addListener(_onRepoChanged);
    _maybePlayGuide();
  }

  @override
  void dispose() {
    SoundRepository.instance.removeListener(_onRepoChanged);
    _breath.dispose();
    _guide.dispose();
    super.dispose();
  }

  void _onRepoChanged() {
    if (_pendingPressId == null || !mounted) return;
    final item = SoundRepository.instance.get(_pendingPressId!);
    if (item != null && item.status == SoundStatus.collected) {
      setState(() {
        _completeCard = item;
        _pendingPressId = null;
        _trayLocked = false;
        _machineMode = PressMachineMode.idle;
        _dragPhase = _DragPhase.idle;
      });
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _maybePlayGuide() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_kGuideSeenKey) ?? false;
    if (seen || !mounted) return;
    await prefs.setBool(_kGuideSeenKey, true);
    if (!mounted) return;
    setState(() => _showGuideHint = true);
    _guide.forward(from: 0);
  }

  List<SoundMemory> get _items => SoundRepository.instance.drafts;

  bool _canPress(SoundMemory item) =>
      item.status == SoundStatus.drafted ||
      item.status == SoundStatus.writeFailed ||
      item.status == SoundStatus.chainFailed;

  Rect? _slotRectGlobal() {
    final box = _slotKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    // 吸附区大于视觉插槽
    return Rect.fromLTWH(
      topLeft.dx - 36,
      topLeft.dy - 48,
      box.size.width + 72,
      box.size.height + 100,
    );
  }

  Rect? _stageRectGlobal() {
    final box = _stageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _onLongPressCenter(LongPressStartDetails details, int index) {
    if (_trayLocked || _dragPhase != _DragPhase.idle) return;
    final items = _items;
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
      _machineMode = PressMachineMode.receiving;
      _showGuideHint = false;
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
      final slotCenter = slot.center;
      final dist = (next - slotCenter).distance;
      const maxDist = 280.0;
      final t = (1 - (dist / maxDist)).clamp(0.0, 1.0);
      scale = uiLerp(1.04, 0.92, t);
      angle = uiLerp(_dragAngle, 0, 0.15);
      if (slot.contains(next) || dist < 90) {
        mode = PressMachineMode.readyToRelease;
        near = true;
      }
    }

    final wasReady = _machineMode == PressMachineMode.readyToRelease;
    setState(() {
      _dragGlobal = next;
      _dragScale = scale;
      _dragAngle = angle;
      _machineMode = mode;
    });
    if (near && !wasReady) {
      HapticFeedback.lightImpact();
    }
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
    await _acceptIntoMachine();
  }

  Future<void> _springBack() async {
    setState(() => _dragPhase = _DragPhase.snapping);
    await Future<void>.delayed(AppMotion.normal);
    if (!mounted) return;
    setState(() {
      _dragPhase = _DragPhase.idle;
      _dragIndex = null;
      _dragGlobal = null;
      _dragScale = 1;
      _dragAngle = 0;
      _machineMode = PressMachineMode.idle;
    });
  }

  Future<void> _acceptIntoMachine() async {
    final items = _items;
    final index = _dragIndex;
    if (index == null || index >= items.length) {
      await _springBack();
      return;
    }
    final item = items[index];
    final slot = _slotRectGlobal();
    if (slot == null) {
      await _springBack();
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _dragPhase = _DragPhase.snapping;
      _trayLocked = true;
      _dragGlobal = slot.center;
      _dragScale = 0.88;
      _dragAngle = 0;
      _machineMode = PressMachineMode.readyToRelease;
    });
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;

    // 卡片向上吸入
    setState(() {
      _dragPhase = _DragPhase.inserting;
      _dragGlobal = Offset(slot.center.dx, slot.top - 20);
      _dragScale = 0.72;
      _machineMode = PressMachineMode.reading;
    });
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;

    setState(() {
      _dragPhase = _DragPhase.idle;
      _dragIndex = null;
      _dragGlobal = null;
      _machineMode = PressMachineMode.verifying;
    });
    await Future<void>.delayed(const Duration(milliseconds: 360));
    if (!mounted) return;

    setState(() => _machineMode = PressMachineMode.binding);
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;

    _pendingPressId = item.id;
    widget.onPress(item.id);

    // 若未立刻完成（进入 Press 流程），保持锁定直至返回或成功
    if (!mounted) return;
    setState(() {
      _machineMode = PressMachineMode.idle;
      _trayLocked = false;
    });
  }

  void _dismissComplete({required bool viewCollection}) {
    final card = _completeCard;
    setState(() => _completeCard = null);
    if (viewCollection && card != null) {
      // 切到 Collection：由外层 tab 处理；此处打开详情不可用，交给提示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已写入收藏，可在 Collection 查看')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        SoundRepository.instance,
        AuthService.instance,
      ]),
      builder: (context, _) {
        final items = _items;
        final loggedIn = AuthService.instance.isLoggedIn;
        final count = items.length;
        final countLabel = count.toString().padLeft(2, '0');
        final selected = count == 0
            ? 0
            : _selectedIndex.clamp(0, count - 1).toInt();
        if (selected != _selectedIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedIndex = selected);
          });
        }

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
                    // 顶部：单一主标题 + 数量
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 16, 6),
                      child: AnimatedOpacity(
                        duration: AppMotion.fast,
                        opacity: _dragPhase == _DragPhase.dragging ||
                                _dragPhase == _DragPhase.inserting
                            ? 0.35
                            : 1,
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
                                    fontWeight: FontWeight.w400,
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
                    if (!loggedIn)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                        child: LoginHintCard(onLogin: widget.onLogin),
                      ),
                    // 写入机器 ~32%
                    Expanded(
                      flex: 32,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: PressMachine(
                          mode: _machineMode,
                          breath: _breath,
                          guideFlash: _guideFlash,
                          slotKey: _slotKey,
                        ),
                      ),
                    ),
                    // 过渡区：插槽与卡片 32–56px，仅拖动/引导时显示提示
                    SizedBox(
                      height: 44,
                      child: Center(
                        child: AnimatedOpacity(
                          duration: AppMotion.fast,
                          opacity: _dragPhase == _DragPhase.dragging ||
                                  _showGuideHint
                              ? 1
                              : 0,
                          child: Text(
                            _dragPhase == _DragPhase.dragging
                                ? (_machineMode ==
                                        PressMachineMode.readyToRelease
                                    ? 'RELEASE TO PRESS'
                                    : 'DRAG UP TO PRESS')
                                : '将声音拖入机器',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Courier',
                              color: AppColors.accent,
                              fontSize: 11,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 暂存卡片区
                    Expanded(
                      flex: 48,
                      child: items.isEmpty
                          ? _EmptyDrafts(
                              onStartRecord: widget.onStartRecord,
                              onOpenCollection: widget.onOpenCollection,
                            )
                          : DraftTrayCarousel(
                              items: items,
                              selectedIndex: selected,
                              onIndexChanged: (i) =>
                                  setState(() => _selectedIndex = i),
                              onOpenDetail: widget.onOpenDetail,
                              onLongPressCenter: _onLongPressCenter,
                              onLongPressMove: _onLongPressMove,
                              onLongPressEnd: _onLongPressEnd,
                              dimmed: _dragPhase == _DragPhase.dragging ||
                                  _dragPhase == _DragPhase.inserting,
                              locked: _trayLocked ||
                                  _dragPhase == _DragPhase.inserting ||
                                  _dragPhase == _DragPhase.snapping,
                              placeholderIndex: _dragPhase != _DragPhase.idle
                                  ? _dragIndex
                                  : null,
                            ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
                // 拖拽层：不裁切分区
                if (_dragPhase != _DragPhase.idle &&
                    _dragIndex != null &&
                    _dragGlobal != null &&
                    _dragIndex! < items.length)
                  _DragLayer(
                    item: items[_dragIndex!],
                    globalPosition: _dragGlobal!,
                    scale: _dragScale,
                    angle: _dragAngle,
                    inserting: _dragPhase == _DragPhase.inserting ||
                        _dragPhase == _DragPhase.snapping,
                    stageGlobal: _stageRectGlobal(),
                  ),
                if (_completeCard != null)
                  _PressCompleteOverlay(
                    item: _completeCard!,
                    onViewCollection: () =>
                        _dismissComplete(viewCollection: true),
                    onContinue: () =>
                        _dismissComplete(viewCollection: false),
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
    required this.inserting,
    required this.stageGlobal,
  });

  final SoundMemory item;
  final Offset globalPosition;
  final double scale;
  final double angle;
  final bool inserting;
  final Rect? stageGlobal;

  @override
  Widget build(BuildContext context) {
    final origin = stageGlobal?.topLeft ?? Offset.zero;
    final local = globalPosition - origin;
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
                child: Opacity(
                  opacity: inserting ? 0.9 : 1,
                  child: DraftTrayCard(
                    item: item,
                    elevated: true,
                    scale: scale,
                    onTap: () {},
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

class _PressCompleteOverlay extends StatelessWidget {
  const _PressCompleteOverlay({
    required this.item,
    required this.onViewCollection,
    required this.onContinue,
  });

  final SoundMemory item;
  final VoidCallback onViewCollection;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final rarity = item.discRarity;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.72),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
            child: Column(
              children: [
                const Spacer(),
                const Text(
                  'PRESS COMPLETE',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 200,
                  height: 260,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.2),
                        blurRadius: 28,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      ClipOval(
                        child: SizedBox(
                          width: 96,
                          height: 96,
                          child: SoundVisualCanvas(
                            seed: item.visualSeed,
                            mode: SoundVisualMode.complete,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        rarity == null
                            ? 'RARITY'
                            : '${rarity.code} · ${rarity.label}',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '《${item.title}》',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item.discId != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          item.discId!,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Spacer(),
                PrimaryButton(
                  text: '查看收藏',
                  onPressed: onViewCollection,
                ),
                const SizedBox(height: 10),
                SecondaryButton(
                  text: '继续写入',
                  onPressed: onContinue,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyDrafts extends StatefulWidget {
  const _EmptyDrafts({
    required this.onStartRecord,
    required this.onOpenCollection,
  });

  final VoidCallback onStartRecord;
  final VoidCallback onOpenCollection;

  @override
  State<_EmptyDrafts> createState() => _EmptyDraftsState();
}

class _EmptyDraftsState extends State<_EmptyDrafts> {
  late DraftsEmptyKind _kind;

  @override
  void initState() {
    super.initState();
    final repo = SoundRepository.instance;
    _kind = repo.draftsEmptyKind ??
        (repo.everHadDrafts || repo.hasCollectionAssets
            ? DraftsEmptyKind.allPressed
            : DraftsEmptyKind.firstUse);
    // 「清空 / 全部封存」只展示一次，离开后恢复常规空态。
    if (repo.draftsEmptyKind != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SoundRepository.instance.consumeDraftsEmptyKind();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_kind) {
      DraftsEmptyKind.firstUse => EmptyStatePanel(
          statusCode: 'NO SOUND DRAFTS',
          title: '还没有等待封存的声音',
          description: '录下一段声音，它会暂存在这里。',
          visual: const EmptyTrayVisual(),
          primaryLabel: '去录一段声音',
          onPrimary: widget.onStartRecord,
        ),
      DraftsEmptyKind.allPressed => EmptyStatePanel(
          statusCode: 'ALL SOUNDS PROCESSED',
          title: '暂存区声音已经全部封存',
          description: '可以继续去录下一段声音，或查看已经完成的收藏。',
          visual: const EmptyTrayVisual(complete: true),
          variant: EmptyStateVariant.cleared,
          primaryLabel: '继续录音',
          onPrimary: widget.onStartRecord,
          secondaryLabel: '查看收藏',
          onSecondary: widget.onOpenCollection,
        ),
      DraftsEmptyKind.cleared => EmptyStatePanel(
          statusCode: 'DRAFTS CLEARED',
          title: '暂存区现在是空的',
          description: '删除的声音不会进入 Collection。',
          visual: const EmptyTrayVisual(),
          variant: EmptyStateVariant.cleared,
          primaryLabel: '开始新的录音',
          onPrimary: widget.onStartRecord,
        ),
    };
  }
}

class DraftDetailScreen extends StatefulWidget {
  const DraftDetailScreen({
    super.key,
    required this.id,
    required this.onBack,
    required this.onPress,
    required this.onDeleted,
  });

  final String id;
  final VoidCallback onBack;
  final VoidCallback onPress;
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
            child: const Text('确认删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (SoundRepository.instance.delete(widget.id)) {
        widget.onDeleted();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NFC 已写入的声音不可删除，请重试上链')),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: soundCategories.map((c) {
                      final active = c == _category;
                      return GestureDetector(
                        onTap: () => setState(() => _category = c),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.accent.withValues(alpha: 0.15)
                                : AppColors.surface1,
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(
                              color: active
                                  ? AppColors.accent
                                  : AppColors.border,
                            ),
                          ),
                          child: Text(
                            c,
                            style: TextStyle(
                              color: active
                                  ? AppColors.accent
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
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
                  text: item.status == SoundStatus.chainFailed
                      ? '重试上链'
                      : '写入声片',
                  onPressed: widget.onPress,
                ),
                const SizedBox(height: AppSpacing.tight),
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
