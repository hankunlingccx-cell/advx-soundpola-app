import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/press_resume.dart';
import '../../data/sound_repository.dart';
import '../../router/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/sound_visual.dart';

Future<void> resumeAfterAuth(BuildContext context, {bool isNewAccount = false}) async {
  if (isNewAccount) {
    context.go(AppRoutes.accountReady);
    return;
  }
  if (PressResume.hasPending) {
    final id = PressResume.draftId!;
    final chainOnly = PressResume.chainOnly;
    PressResume.clear();
    context.go(AppRoutes.pressMethodPath(id, chainOnly: chainOnly));
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
                    hint: '手机号或邮箱',
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.register(
        account: _accountCtrl.text,
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      await resumeAfterAuth(context, isNewAccount: true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '注册失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              label: '账号',
              hint: '手机号或邮箱',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: AppSpacing.item),
            SpTextField(
              controller: _passwordCtrl,
              label: '密码',
              hint: '至少 6 位',
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
      final chainOnly = PressResume.chainOnly;
      PressResume.clear();
      context.go(AppRoutes.pressMethodPath(id, chainOnly: chainOnly));
    } else {
      context.go(AppRoutes.main);
    }
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
                    Text(
                      user?.walletShort ?? '—',
                      style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w500),
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
