import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../data/press_resume.dart';
import '../../data/sound_repository.dart';
import '../../router/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/deep_link_service.dart';
import '../../services/mint_pipeline.dart';
import '../../services/visual_shape_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/sound_visual.dart';

Future<void> resumeAfterAuth(BuildContext context, {bool isNewAccount = false}) async {
  if (isNewAccount) {
    context.go(AppRoutes.accountReady);
    return;
  }
  if (PendingDeepLink.hasPending) {
    final contentId = PendingDeepLink.contentId!;
    PendingDeepLink.clear();
    context.go(AppRoutes.contentPath(contentId));
    return;
  }
  if (PressResume.hasPending) {
    final id = PressResume.draftId!;
    final isMint = PressResume.entry == 'mint';
    PressResume.clear();
    if (isMint) {
      MintPipeline.instance.startCloud(id);
      context.go(AppRoutes.mainTab(1));
    } else {
      context.go(AppRoutes.pressMethodPath(id));
    }
    return;
  }
  context.go(AppRoutes.main);
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.draftId});

  final String? draftId;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _accountCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  bool _remember = false;
  String? _error;

  SoundMemory? get _draft {
    final id = widget.draftId ?? PressResume.draftId;
    if (id == null) return null;
    return SoundRepository.instance.get(id);
  }

  bool get _canSkip => PressResume.hasPending || widget.draftId != null;

  @override
  void initState() {
    super.initState();
    _restoreRemembered();
  }

  Future<void> _restoreRemembered() async {
    final saved = await AuthService.instance.loadRememberedCredentials();
    if (!mounted) return;
    setState(() {
      _remember = saved.remember;
      if (saved.account.isNotEmpty) _accountCtrl.text = saved.account;
      if (saved.password.isNotEmpty) _passwordCtrl.text = saved.password;
    });
  }

  @override
  void dispose() {
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.login(
        account: _accountCtrl.text,
        password: _passwordCtrl.text,
      );
      await AuthService.instance.saveRememberedCredentials(
        remember: _remember,
        account: _accountCtrl.text,
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      await resumeAfterAuth(context);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '登录失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _later() {
    final draftId = PressResume.draftId ?? widget.draftId;
    PressResume.clear();
    if (draftId != null) {
      context.go(AppRoutes.draftPath(draftId));
    } else {
      context.go(AppRoutes.main);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: Stack(
          children: [
            const Positioned(
              left: -140,
              right: -140,
              bottom: -120,
              height: 280,
              child: _LoginAmbientGlow(),
            ),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pageHorizontal,
                ),
                children: [
                  const SizedBox(height: AppSpacing.item),
                  if (_canSkip)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _later,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textTertiary,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('稍后再说'),
                      ),
                    )
                  else
                    const SizedBox(height: AppSpacing.section),
                  const Text(
                    'SoundPola',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (draft != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      child: SizedBox(
                        height: 160,
                        child: ColoredBox(
                          color: AppColors.surface1,
                          child: SoundVisualCanvas(
                            seed: draft.visualSeed,
                            mode: SoundVisualMode.complete,
                            shape: VisualShapeService.instance
                                .peek(draft.visualPath),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.item),
                    Text(
                      draft.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    draft != null
                        ? '登录后，这段声音将归属于你的数字收藏。'
                        : '登录后开始捕捉声音，并写入声片与数字收藏。',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  _AuthPillField(
                    controller: _accountCtrl,
                    hint: '邮箱',
                    icon: Icons.person_rounded,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 20),
                  _AuthPillField(
                    controller: _passwordCtrl,
                    hint: '请输入密码',
                    icon: Icons.lock_rounded,
                    obscure: true,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.tight),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _RememberPasswordRow(
                    value: _remember,
                    onChanged: (v) => setState(() => _remember = v),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  _AuthPillButton(
                    text: _busy ? '登录中…' : '登录',
                    filled: true,
                    onPressed: _busy ? null : _submit,
                  ),
                  const SizedBox(height: 10),
                  _AuthPillButton(
                    text: '注册账号',
                    filled: false,
                    onPressed: () => context.push(AppRoutes.register),
                  ),
                  const SizedBox(height: AppSpacing.item),
                  const Text(
                    '继续即表示你同意用户协议与隐私政策。账号与数字资产账户仅保存在本机（MVP）。',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.block),
                ],
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4, top: 4),
                  child: IconButton(
                    tooltip: '服务器设置',
                    onPressed: () => context.push(AppRoutes.serverSettings),
                    icon: SvgPicture.asset(
                      'assets/icons/settings.svg',
                      width: 22,
                      height: 22,
                      colorFilter: const ColorFilter.mode(
                        AppColors.textSecondary,
                        BlendMode.srcIn,
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

class _LoginAmbientGlow extends StatelessWidget {
  const _LoginAmbientGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 72, sigmaY: 72),
        child: Center(
          child: Container(
            width: 420,
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(200),
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF7FECFF).withValues(alpha: 0.55),
                  AppColors.accent.withValues(alpha: 0.42),
                  AppColors.accent.withValues(alpha: 0),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthPillField extends StatelessWidget {
  const _AuthPillField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;

  static const _fill = Color(0xFF171717);
  static const _radius = 30.0;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w400,
      ),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 20, right: 12),
          child: Icon(
            icon,
            size: 20,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 52, minHeight: 20),
        filled: true,
        fillColor: _fill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
        ),
      ),
    );
  }
}

class _RememberPasswordRow extends StatelessWidget {
  const _RememberPasswordRow({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: AppMotion.fast,
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.textPrimary, width: 1),
              color: value ? AppColors.accent : Colors.transparent,
            ),
            child: value
                ? const Icon(Icons.check, size: 12, color: AppColors.accentOn)
                : null,
          ),
          const SizedBox(width: 8),
          const Text(
            '记住密码',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthPillButton extends StatelessWidget {
  const _AuthPillButton({
    required this.text,
    required this.filled,
    required this.onPressed,
  });

  final String text;
  final bool filled;
  final VoidCallback? onPressed;

  static const _radius = 30.0;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    if (filled) {
      return SizedBox(
        width: double.infinity,
        height: AppSizes.buttonHeight,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: enabled ? AppColors.accent : AppColors.surface2,
            foregroundColor: enabled ? AppColors.accentOn : AppColors.textTertiary,
            disabledBackgroundColor: AppColors.surface2,
            disabledForegroundColor: AppColors.textTertiary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius),
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 16),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: AppSizes.buttonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          backgroundColor: Colors.transparent,
          side: BorderSide(color: const Color(0xFF393939).withValues(alpha: 0.69)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 16),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _accountCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }
    final storeInCloud = await _askKeyStorage(context);
    if (storeInCloud == null) return; // 用户取消
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.register(
        account: _accountCtrl.text,
        password: _passwordCtrl.text,
        storePrivateKey: storeInCloud,
      );
      if (!mounted) return;
      if (storeInCloud) {
        await resumeAfterAuth(context, isNewAccount: true);
      } else {
        context.go(AppRoutes.privateKeyBackup);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '注册失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Returns true = 云端托管, false = 本地保存, null = 取消。
  Future<bool?> _askKeyStorage(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '如何保存你的私钥？',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '私钥用于掌控你的数字收藏。云端托管更省心，本地保存更自主。',
                style: TextStyle(color: AppColors.textSecondary, height: 1.5, fontSize: 14),
              ),
              const SizedBox(height: AppSpacing.section),
              _KeyStorageOption(
                title: '云端托管（推荐）',
                subtitle: '由系统安全托管，换机也不会丢失，直接进入即可使用。',
                icon: Icons.cloud_done_rounded,
                onTap: () => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: AppSpacing.tight),
              _KeyStorageOption(
                title: '本地保存',
                subtitle: '私钥仅显示一次并保存在本机。请务必自行备份，清除数据将丢失。',
                icon: Icons.vpn_key_rounded,
                onTap: () => Navigator.pop(ctx, false),
              ),
              const SizedBox(height: AppSpacing.item),
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消', style: TextStyle(color: AppColors.textTertiary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('注册'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal),
          children: [
            const SizedBox(height: AppSpacing.item),
            const Text(
              '创建账号后，系统将为你生成托管的数字资产账户。',
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.section),
            SpTextField(
              controller: _accountCtrl,
              label: '邮箱',
              hint: '请输入邮箱',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: AppSpacing.item),
            SpTextField(
              controller: _passwordCtrl,
              label: '密码',
              hint: '至少 8 位',
              obscure: true,
            ),
            const SizedBox(height: AppSpacing.item),
            SpTextField(
              controller: _confirmCtrl,
              label: '确认密码',
              hint: '再次输入密码',
              obscure: true,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.tight),
              Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ],
            const SizedBox(height: AppSpacing.section),
            PrimaryButton(
              text: _busy ? '创建中…' : '创建账号',
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: AppSpacing.section),
          ],
        ),
      ),
    );
  }
}

class AccountReadyScreen extends StatelessWidget {
  const AccountReadyScreen({super.key});

  void _continue(BuildContext context) {
    if (PressResume.hasPending) {
      final id = PressResume.draftId!;
      final isMint = PressResume.entry == 'mint';
      PressResume.clear();
      if (isMint) {
        MintPipeline.instance.startCloud(id);
        context.go(AppRoutes.mainTab(1));
      } else {
        context.go(AppRoutes.pressMethodPath(id));
      }
    } else {
      context.go(AppRoutes.main);
    }
  }

  Future<void> _copyWallet(BuildContext context, String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('钱包地址已复制'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.block),
              const Text(
                '数字资产账户已创建',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '密钥由系统安全托管。你无需理解链上术语，即可收藏声音记忆。',
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.section),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                decoration: BoxDecoration(
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.nickname ?? '收藏者',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user?.accountMasked ?? '',
                      style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                    ),
                    const SizedBox(height: AppSpacing.item),
                    const Text('数字资产账户', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: user?.walletAddress == null
                          ? null
                          : () => _copyWallet(context, user!.walletAddress),
                      borderRadius: BorderRadius.circular(AppRadii.button),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                user?.walletShort ?? '—',
                                style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w500),
                              ),
                            ),
                            if (user?.walletAddress != null) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.copy_rounded,
                                size: 15,
                                color: AppColors.accent,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              PrimaryButton(
                text: PressResume.hasPending ? '继续写入声片' : '开始使用',
                onPressed: () => _continue(context),
              ),
              const SizedBox(height: AppSpacing.section),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyStorageOption extends StatelessWidget {
  const _KeyStorageOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.accent, size: 24),
            const SizedBox(width: AppSpacing.item),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class PrivateKeyBackupScreen extends StatefulWidget {
  const PrivateKeyBackupScreen({super.key});

  @override
  State<PrivateKeyBackupScreen> createState() => _PrivateKeyBackupScreenState();
}

class _PrivateKeyBackupScreenState extends State<PrivateKeyBackupScreen> {
  String? _privateKey;

  @override
  void initState() {
    super.initState();
    _privateKey = AuthService.instance.consumePendingPrivateKey();
  }

  Future<void> _copy() async {
    final pk = _privateKey;
    if (pk == null) return;
    await Clipboard.setData(ClipboardData(text: pk));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('私钥已复制到剪贴板')),
    );
  }

  void _continue() {
    if (PressResume.hasPending) {
      final id = PressResume.draftId!;
      final isMint = PressResume.entry == 'mint';
      PressResume.clear();
      if (isMint) {
        MintPipeline.instance.startCloud(id);
        context.go(AppRoutes.mainTab(1));
      } else {
        context.go(AppRoutes.pressMethodPath(id));
      }
    } else {
      context.go(AppRoutes.main);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pk = _privateKey;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal),
            children: [
              const SizedBox(height: AppSpacing.block),
              const Text(
                '请备份你的私钥',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '私钥已自动保存到本机安全存储。请再复制一份离线备份：\n'
                '· 私钥仅显示这一次\n'
                '· 更换设备或清除应用数据将导致丢失\n'
                '· 拥有私钥即可掌控你的数字收藏，切勿泄露',
                style: TextStyle(color: AppColors.textSecondary, height: 1.6, fontSize: 14),
              ),
              const SizedBox(height: AppSpacing.section),
              if (pk != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('私钥', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                      const SizedBox(height: 8),
                      SelectableText(
                        pk,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          height: 1.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.item),
                SecondaryButton(text: '复制私钥', onPressed: _copy),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    '私钥仅显示一次，当前已不可再次读取。你可以稍后在「账户」页重新配置本地私钥。',
                    style: TextStyle(color: AppColors.textSecondary, height: 1.5, fontSize: 14),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.block),
              PrimaryButton(text: '我已保存，继续', onPressed: _continue),
              const SizedBox(height: AppSpacing.section),
            ],
          ),
        ),
      ),
    );
  }
}
