import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../data/sound_repository.dart';
import '../../router/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/sound_visual.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text(
          '本机为该账号保留的 Drafts 会在再次登录同一账号后恢复；其他账号不可见。'
          'Collection 以云端为准，需重新登录后同步。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AuthService.instance.logout();
      if (context.mounted) context.go(AppRoutes.login);
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
    return AnimatedBuilder(
      animation: Listenable.merge([
        AuthService.instance,
        SoundRepository.instance,
      ]),
      builder: (context, _) {
        final user = AuthService.instance.currentUser;
        final collectionCount = SoundRepository.instance.collection.length;
        final discCount = SoundRepository.instance.collection
            .where((s) => s.discId != null)
            .length;

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          appBar: AppBar(
            title: const Text('Account'),
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
                if (user == null) ...[
                  const Text(
                    '尚未登录',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '登录后可将声音写入声片并创建数字收藏。',
                    style: TextStyle(color: AppColors.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  PrimaryButton(
                    text: '登录 / 注册',
                    onPressed: () => context.push(AppRoutes.login),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surface2,
                          border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          user.initial,
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.item),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.nickname,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user.accountMasked,
                              style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.section),
                  Row(
                    children: [
                      _StatTile(label: '收藏', value: '$collectionCount'),
                      const SizedBox(width: AppSpacing.tight),
                      _StatTile(label: '声片', value: '$discCount'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.section),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    decoration: BoxDecoration(
                      color: AppColors.surface1,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '数字资产账户',
                          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => _copyWallet(context, user.walletAddress),
                          borderRadius: BorderRadius.circular(AppRadii.button),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    user.walletShort,
                                    style: const TextStyle(
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.copy_rounded,
                                  size: 15,
                                  color: AppColors.accent,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '托管账户 · 账号状态正常',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  const _LocalPrivateKeySection(),
                  if (SoundRepository.instance.collection.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.section),
                    const Text(
                      '最近收藏',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.tight),
                    SizedBox(
                      height: 110,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: SoundRepository.instance.collection.take(6).length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final item = SoundRepository.instance.collection[index];
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.card),
                            child: SizedBox(
                              width: 110,
                              child: ColoredBox(
                                color: AppColors.surface1,
                                child: SoundVisualCanvas(
                                  seed: item.visualSeed,
                                  mode: SoundVisualMode.complete,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.block),
                  PrimaryButton(
                    text: 'WiFi 扫码连接设备',
                    onPressed: () => context.push(AppRoutes.pairDevice),
                  ),
                  const SizedBox(height: AppSpacing.item),
                  SecondaryButton(
                    text: '我的设备',
                    onPressed: () => context.push(AppRoutes.myDevices),
                  ),
                  const SizedBox(height: AppSpacing.item),
                  SecondaryButton(
                    text: 'Sound Lab 声音实验室',
                    onPressed: () => context.push(AppRoutes.soundLab),
                  ),
                  const SizedBox(height: AppSpacing.item),
                  SecondaryButton(
                    text: '退出登录',
                    danger: true,
                    onPressed: () => _logout(context),
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

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: AppColors.textTertiary, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _LocalPrivateKeySection extends StatefulWidget {
  const _LocalPrivateKeySection();

  @override
  State<_LocalPrivateKeySection> createState() => _LocalPrivateKeySectionState();
}

class _LocalPrivateKeySectionState extends State<_LocalPrivateKeySection> {
  final _inputCtrl = TextEditingController();
  String? _stored;
  bool _loading = true;
  bool _revealed = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final pk = await AuthService.instance.readLocalPrivateKey();
    if (!mounted) return;
    setState(() {
      _stored = pk;
      _loading = false;
    });
  }

  String _mask(String pk) {
    if (pk.length <= 12) return pk;
    return '${pk.substring(0, 6)}…${pk.substring(pk.length - 4)}';
  }

  Future<void> _copy() async {
    final pk = _stored;
    if (pk == null) return;
    await Clipboard.setData(ClipboardData(text: pk));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('私钥已复制到剪贴板')),
    );
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除本地私钥？'),
        content: const Text('清除后本机将不再保存私钥。如未备份，将无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AuthService.instance.clearLocalPrivateKey();
    if (!mounted) return;
    setState(() {
      _stored = null;
      _revealed = false;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AuthService.instance.saveLocalPrivateKey(_inputCtrl.text);
      _inputCtrl.clear();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('私钥已保存到本机')),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '本地私钥',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '私钥仅保存在本机安全存储，不会上传。请自行妥善备份。',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.item),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_stored != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(AppRadii.button),
              ),
              child: SelectableText(
                _revealed ? _stored! : _mask(_stored!),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _KeyActionChip(
                  icon: _revealed ? Icons.visibility_off : Icons.visibility,
                  label: _revealed ? '隐藏' : '显示',
                  onTap: () => setState(() => _revealed = !_revealed),
                ),
                _KeyActionChip(icon: Icons.copy, label: '复制', onTap: _copy),
                _KeyActionChip(
                  icon: Icons.delete_outline,
                  label: '清除',
                  danger: true,
                  onTap: _clear,
                ),
              ],
            ),
          ] else
            const Text(
              '尚未配置本地私钥。可在下方粘贴并保存。',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
          const SizedBox(height: AppSpacing.item),
          TextField(
            controller: _inputCtrl,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontFamily: 'monospace'),
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              hintText: '粘贴私钥（0x 开头，64 位十六进制）',
              hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
              filled: true,
              fillColor: AppColors.surface2,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.button),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.button),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.button),
                borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          SecondaryButton(
            text: _saving ? '保存中…' : '保存到本机',
            onPressed: _saving ? () {} : _save,
          ),
        ],
      ),
    );
  }
}

class _KeyActionChip extends StatelessWidget {
  const _KeyActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
