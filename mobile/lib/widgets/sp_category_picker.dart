import 'package:flutter/material.dart';
import '../data/sound_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 用户自定义分类选择器：展示已创建分类，并支持新建。
class SpCategoryPicker extends StatefulWidget {
  const SpCategoryPicker({super.key, this.current});

  final String? current;

  /// 弹出底部 sheet，返回选中／新建的分类名。
  static Future<String?> show(
    BuildContext context, {
    String? current,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
      ),
      builder: (ctx) => SpCategoryPicker(current: current),
    );
  }

  @override
  State<SpCategoryPicker> createState() => _SpCategoryPickerState();
}

class _SpCategoryPickerState extends State<SpCategoryPicker> {
  bool _creating = false;
  final _createCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _createCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitCreate() async {
    final raw = _createCtrl.text;
    final name = await SoundRepository.instance.addCategory(raw);
    if (!mounted) return;
    if (name == null) {
      setState(() {
        _error = raw.trim().isEmpty
            ? '请输入分类名称'
            : '名称需在 $kCategoryNameMaxLength 字以内';
      });
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // 键盘弹出时压缩 sheet，列表用 Flexible 让出高度，避免 BOTTOM OVERFLOW。
    final sheetCap = mq.size.height * 0.72;

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight.clamp(0.0, sheetCap)
                : sheetCap;
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: ListenableBuilder(
                listenable: SoundRepository.instance,
                builder: (context, _) {
                  final categories = SoundRepository.instance.categories;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '选择分类',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            '取消',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (categories.isEmpty && !_creating)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Text(
                        '还没有分类，创建一个',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: categories.length,
                        itemBuilder: (context, index) {
                          final c = categories[index];
                          final selected = c == widget.current;
                          return ListTile(
                            title: Text(
                              c,
                              style: TextStyle(
                                color: selected
                                    ? AppColors.accent
                                    : AppColors.textPrimary,
                              ),
                            ),
                            trailing: selected
                                ? const Icon(
                                    Icons.check,
                                    color: AppColors.accent,
                                    size: 18,
                                  )
                                : null,
                            onTap: () => Navigator.of(context).pop(c),
                          );
                        },
                      ),
                    ),
                  const Divider(height: 1, color: AppColors.border),
                  if (_creating)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _createCtrl,
                            autofocus: true,
                            maxLength: kCategoryNameMaxLength,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              hintText: '新分类名称',
                              hintStyle: const TextStyle(
                                color: AppColors.textTertiary,
                              ),
                              errorText: _error,
                              counterStyle: const TextStyle(
                                color: AppColors.textTertiary,
                              ),
                              filled: true,
                              fillColor: AppColors.surface1,
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadii.input),
                                borderSide:
                                    const BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadii.input),
                                borderSide:
                                    const BorderSide(color: AppColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadii.input),
                                borderSide:
                                    const BorderSide(color: AppColors.accent),
                              ),
                            ),
                            onChanged: (_) {
                              if (_error != null) {
                                setState(() => _error = null);
                              }
                            },
                            onSubmitted: (_) => _submitCreate(),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => setState(() {
                                  _creating = false;
                                  _error = null;
                                  _createCtrl.clear();
                                }),
                                child: const Text(
                                  '返回',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: _submitCreate,
                                child: const Text(
                                  '创建并选用',
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    ListTile(
                      leading: const Icon(Icons.add, color: AppColors.accent),
                      title: const Text(
                        '创建新分类',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () => setState(() => _creating = true),
                    ),
                  const SizedBox(height: 8),
                ],
              );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
