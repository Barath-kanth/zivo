import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/task/task_bloc.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';

/// Feature 5 — One problem → several tasks + bundle checkout.
Future<void> showTaskBundlePlanner(
  BuildContext context, {
  String? initialProblem,
  String? categoryHint,
  String? bookedForName,
  String? bookedForUserId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _TaskBundleSheet(
      initialProblem: initialProblem ?? '',
      categoryHint: categoryHint,
      bookedForName: bookedForName,
      bookedForUserId: bookedForUserId,
    ),
  );
}

class _TaskBundleSheet extends StatefulWidget {
  const _TaskBundleSheet({
    required this.initialProblem,
    this.categoryHint,
    this.bookedForName,
    this.bookedForUserId,
  });

  final String initialProblem;
  final String? categoryHint;
  final String? bookedForName;
  final String? bookedForUserId;

  @override
  State<_TaskBundleSheet> createState() => _TaskBundleSheetState();
}

class _TaskBundleSheetState extends State<_TaskBundleSheet> {
  late final TextEditingController _problemCtrl;
  bool _planning = false;
  bool _checkingOut = false;
  String? _bundleTitle;
  String? _explanation;
  List<Map<String, dynamic>> _drafts = const [];
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _problemCtrl = TextEditingController(text: widget.initialProblem);
  }

  @override
  void dispose() {
    _problemCtrl.dispose();
    super.dispose();
  }

  Future<void> _plan() async {
    final problem = _problemCtrl.text.trim();
    if (problem.length < 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Describe the full problem (12+ characters)')),
      );
      return;
    }
    setState(() => _planning = true);
    try {
      final res = await context.read<TaskRepository>().planTaskBundle(
            problem: problem,
            categoryHint: widget.categoryHint,
          );
      if (!mounted) return;
      final tasks = (res['tasks'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      setState(() {
        _planning = false;
        _bundleTitle = res['bundle_title']?.toString() ?? 'Help bundle';
        _explanation = res['explanation']?.toString();
        _drafts = tasks;
        _selected
          ..clear()
          ..addAll(List.generate(tasks.length, (i) => i));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _planning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanizeError(e)),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  Future<void> _checkout() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one task')),
      );
      return;
    }
    setState(() => _checkingOut = true);
    try {
      final tasks = _selected.map((i) {
        final t = _drafts[i];
        return {
          'title': t['title'],
          'description': t['description'],
          'category': t['category'],
          'estimated_hours': (t['estimated_hours'] as num?)?.toDouble() ?? 1,
          'goods_budget': (t['goods_budget'] as num?)?.toDouble() ?? 0,
        };
      }).toList();

      final deadline = DateTime.now()
          .add(const Duration(hours: 48))
          .toUtc()
          .toIso8601String();

      final res = await context.read<TaskRepository>().checkoutTaskBundle(
            bundleTitle: _bundleTitle ?? 'Help bundle',
            lat: 6.9271,
            lon: 79.8612,
            locationLabel: 'Near me',
            deadlineAt: deadline,
            tasks: tasks,
            bookedForName: widget.bookedForName,
            bookedForUserId: widget.bookedForUserId,
          );
      if (!mounted) return;

      final auth = context.read<AuthBloc>().state;
      if (auth is AuthAuthenticated) {
        context.read<TaskBloc>().add(TaskFetchClientTasks(auth.profile.id));
      }

      final hold = res['total_hold_lkr'];
      final count = (res['tasks'] as List?)?.length ?? tasks.length;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bundle posted · $count tasks · escrow ${AppConfig.money(num.tryParse('$hold') ?? 0)}',
          ),
          backgroundColor: AppColors.successColor,
        ),
      );
      context.go(AppRoutes.shell);
    } catch (e) {
      if (!mounted) return;
      setState(() => _checkingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanizeError(e)),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom + viewInsets),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const Gap(14),
            Text('Split into tasks', style: AppTextStyles.headingMedium),
            const Gap(4),
            Text(
              'One problem → several related jobs. Select what you need, then checkout as one bundle.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
            ),
            if (widget.bookedForName != null) ...[
              const Gap(8),
              Text(
                'Booking for ${widget.bookedForName}',
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.helperAccent,
                ),
              ),
            ],
            const Gap(12),
            TextField(
              controller: _problemCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Describe the full problem',
                hintText: 'e.g. Moving to a new flat this weekend — pack, load, and clean',
                border: OutlineInputBorder(),
              ),
            ),
            const Gap(10),
            FilledButton.icon(
              onPressed: _planning || _checkingOut ? null : _plan,
              icon: _planning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_planning ? 'Planning…' : 'Suggest related tasks'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
            ),
            if (_explanation != null) ...[
              const Gap(12),
              Text(_explanation!, style: AppTextStyles.bodySmall),
            ],
            if (_drafts.isNotEmpty) ...[
              const Gap(12),
              Text(
                _bundleTitle ?? 'Bundle',
                style: AppTextStyles.headingSmall,
              ),
              const Gap(8),
              ...List.generate(_drafts.length, (i) {
                final t = _drafts[i];
                final on = _selected.contains(i);
                return CheckboxListTile(
                  value: on,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selected.add(i);
                      } else {
                        _selected.remove(i);
                      }
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    t['title']?.toString() ?? 'Task',
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${t['category']} · ~${t['estimated_hours']}h'
                    '${((t['goods_budget'] as num?) ?? 0) > 0 ? ' · goods ${AppConfig.money(t['goods_budget'] as num)}' : ''}\n'
                    '${t['description']}',
                    style: AppTextStyles.bodySmall,
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }),
              const Gap(8),
              FilledButton(
                onPressed: _checkingOut || _selected.isEmpty ? null : _checkout,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.helperAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  _checkingOut
                      ? 'Checking out…'
                      : 'Checkout bundle (${_selected.length})',
                ),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
