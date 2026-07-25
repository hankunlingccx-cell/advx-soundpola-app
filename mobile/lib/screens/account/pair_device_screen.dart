import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/auth_service.dart';
import '../../services/device_pair_service.dart';
import '../../services/permission_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';

enum _PairState { loading, noPermission, scanning, sending, success, error }

class PairDeviceScreen extends StatefulWidget {
  const PairDeviceScreen({super.key});

  @override
  State<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends State<PairDeviceScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  _PairState _state = _PairState.loading;
  String _message = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final granted = await PermissionService.ensureCamera();
    if (!mounted) return;
    setState(() {
      _state = granted ? _PairState.scanning : _PairState.noPermission;
    });
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _state != _PairState.scanning) return;
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    final target = DevicePairService.parseQr(raw);
    if (target == null) return; // 非配对码，继续扫描

    _busy = true;
    await _controller.stop();
    if (!mounted) return;
    setState(() => _state = _PairState.sending);

    try {
      final token = await AuthService.instance.requireCloudToken();
      await DevicePairService.sendToken(
        target: target,
        token: token,
        userId: AuthService.instance.cloudUserId,
        email: AuthService.instance.currentUser?.account,
      );
      if (!mounted) return;
      setState(() => _state = _PairState.success);
    } on AuthException catch (e) {
      _fail(e.message);
    } on DevicePairException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('配对失败，请重试');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _state = _PairState.error;
      _message = message;
    });
  }

  Future<void> _rescan() async {
    setState(() {
      _state = _PairState.scanning;
      _message = '';
      _busy = false;
    });
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('配对 NFC 设备'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.item),
              const Text(
                '扫描设备屏幕上显示的二维码，将当前账号授权给设备。',
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.item),
              Expanded(child: _buildBody()),
              const SizedBox(height: AppSpacing.item),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _PairState.loading:
        return const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );

      case _PairState.noPermission:
        return _MessagePanel(
          icon: Icons.no_photography_rounded,
          text: '需要相机权限才能扫描二维码。',
          action: SecondaryButton(
            text: '打开系统设置',
            onPressed: () => PermissionService.openSettings(),
          ),
        );

      case _PairState.scanning:
      case _PairState.sending:
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: _controller, onDetect: _onDetect),
              _ScanOverlay(),
              if (_state == _PairState.sending)
                Container(
                  color: AppColors.bgPrimary.withValues(alpha: 0.6),
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(height: 12),
                      Text(
                        '正在授权设备…',
                        style: TextStyle(color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

      case _PairState.success:
        return _MessagePanel(
          icon: Icons.check_circle_rounded,
          iconColor: AppColors.accent,
          text: '设备配对成功，已授权当前账号。',
          action: PrimaryButton(text: '完成', onPressed: () => context.pop()),
        );

      case _PairState.error:
        return _MessagePanel(
          icon: Icons.error_outline_rounded,
          iconColor: AppColors.error,
          text: _message,
          action: SecondaryButton(text: '重新扫描', onPressed: _rescan),
        );
    }
  }
}

class _ScanOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth * 0.7;
        return Stack(
          children: [
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                AppColors.bgPrimary.withValues(alpha: 0.45),
                BlendMode.srcOut,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Center(
                    child: Container(
                      width: side,
                      height: side,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(AppRadii.card),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Center(
              child: Container(
                width: side,
                height: side,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  border: Border.all(color: AppColors.accent, width: 2),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Text(
                '将二维码对准框内',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary.withValues(alpha: 0.9),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.text,
    required this.action,
    this.iconColor = AppColors.textTertiary,
  });

  final IconData icon;
  final Color iconColor;
  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: iconColor),
          const SizedBox(height: AppSpacing.item),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.item),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          SizedBox(width: 200, child: action),
        ],
      ),
    );
  }
}
