import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
import 'package:hyperlocal/core/utils/speak_text.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/ui/_shared/zivo_logo.dart';

/// Family Assist — public live board for a shared token (no OTP secrets).
class SharedLiveScreen extends StatefulWidget {
  const SharedLiveScreen({super.key, required this.token});
  final String token;

  @override
  State<SharedLiveScreen> createState() => _SharedLiveScreenState();
}

class _SharedLiveScreenState extends State<SharedLiveScreen> {
  Map<String, dynamic>? _live;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load(speak: true);
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool speak = false}) async {
    try {
      final live =
          await context.read<TaskRepository>().getSharedLive(widget.token);
      if (!mounted) return;
      final prev = _live?['status']?.toString();
      setState(() {
        _live = live;
        _error = null;
      });
      if (speak || (prev != null && prev != live['status']?.toString())) {
        final line =
            '${live['status_label'] ?? live['status']}. ${live['updated_hint'] ?? ''}';
        speakText(line);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = humanizeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = _live;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Family live'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _error != null
            ? Center(
                child: Text(
                  _error!,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.errorColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            : live == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ZivoLogo(size: 36, showWordmark: true),
                      const Gap(20),
                      if (live['bundle_title'] != null) ...[
                        Text(
                          live['bundle_title'].toString(),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                        const Gap(4),
                      ],
                      Text(
                        live['title']?.toString() ?? 'Request',
                        style: AppTextStyles.headingLarge.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (live['booked_for_name'] != null) ...[
                        const Gap(6),
                        Text(
                          'For ${live['booked_for_name']}',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const Gap(20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.helperAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              live['status_label']?.toString() ??
                                  live['status']?.toString() ??
                                  '',
                              style: AppTextStyles.headingSmall.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Gap(6),
                            Text(
                              live['updated_hint']?.toString() ?? '',
                              style: AppTextStyles.bodyMedium,
                            ),
                            if (live['helper_name'] != null) ...[
                              const Gap(8),
                              Text(
                                'Helper: ${live['helper_name']}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Gap(16),
                      Text(
                        'This page refreshes automatically. No passwords or OTP codes are shown here.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () {
                          final line =
                              '${live['status_label']}. ${live['updated_hint']}';
                          speakText(line);
                        },
                        icon: const Icon(Icons.volume_up_rounded),
                        label: const Text('Read status aloud'),
                      ),
                    ],
                  ),
      ),
    );
  }
}
