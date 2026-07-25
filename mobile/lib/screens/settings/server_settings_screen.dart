import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../cloud/cloud_media_config.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';

/// 登录管理：配置 Cloud Media 服务器地址（默认预设固定域名）。
class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  bool _https = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  void _loadCurrent() {
    final uri = Uri.tryParse(CloudMediaConfig.baseUrl);
    if (uri != null) {
      _https = uri.scheme == 'https';
      _hostCtrl.text = uri.host;
      if (uri.hasPort) {
        _portCtrl.text = uri.port.toString();
      } else {
        _portCtrl.clear();
      }
    }
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  String get _preview {
    final host = _hostCtrl.text.trim();
    final port = _portCtrl.text.trim();
    final scheme = _https ? 'https' : 'http';
    if (host.isEmpty) return '$scheme://…';
    return port.isEmpty ? '$scheme://$host' : '$scheme://$host:$port';
  }

  Future<void> _save() async {
    final host = _hostCtrl.text.trim();
    final portText = _portCtrl.text.trim();
    if (host.isEmpty) {
      setState(() => _error = '请输入服务器 IP 或域名');
      return;
    }
    if (host.contains('://') || host.contains('/')) {
      setState(() => _error = '只需填写 IP 或域名，不要包含 http:// 或路径');
      return;
    }
    if (portText.isNotEmpty) {
      final port = int.tryParse(portText);
      if (port == null || port < 1 || port > 65535) {
        setState(() => _error = '端口需为 1–65535 之间的数字');
        return;
      }
    }
    final scheme = _https ? 'https' : 'http';
    final url =
        portText.isEmpty ? '$scheme://$host' : '$scheme://$host:$portText';
    await CloudMediaConfig.save(url);
    if (!mounted) return;
    setState(() => _error = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存服务器地址：$url')),
    );
  }

  Future<void> _reset() async {
    await CloudMediaConfig.reset();
    if (!mounted) return;
    setState(() => _error = null);
    _loadCurrent();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已恢复预设：http://soundpola.babelbeast.com:9000'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('服务器设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal,
          ),
          children: [
            const SizedBox(height: AppSpacing.item),
            const Text(
              '登录服务器',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '预设地址为 soundpola.babelbeast.com:9000。一般无需修改；仅在联调或切换环境时改写。',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.section),
            const SectionLabel('协议'),
            _SchemeToggle(
              https: _https,
              onChanged: (v) => setState(() => _https = v),
            ),
            const SizedBox(height: AppSpacing.item),
            SpTextField(
              controller: _hostCtrl,
              label: '服务器 IP 或域名',
              hint: 'soundpola.babelbeast.com',
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.item),
            SpTextField(
              controller: _portCtrl,
              label: '端口（可选）',
              hint: '默认 9000',
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.item),
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
                  const Text(
                    '当前地址',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _preview,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (!CloudMediaConfig.hasOverride) ...[
                    const SizedBox(height: 6),
                    const Text(
                      '（使用预设地址）',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.tight),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: AppSpacing.section),
            PrimaryButton(text: '保存', onPressed: _save),
            const SizedBox(height: AppSpacing.tight),
            SecondaryButton(text: '恢复预设', onPressed: _reset),
            const SizedBox(height: AppSpacing.block),
          ],
        ),
      ),
    );
  }
}

class _SchemeToggle extends StatelessWidget {
  const _SchemeToggle({required this.https, required this.onChanged});

  final bool https;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _segment('http', !https, () => onChanged(false)),
          _segment('https', https, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _segment(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.accentOn : AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
