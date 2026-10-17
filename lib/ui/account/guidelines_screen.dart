import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/community_guidelines.dart';

class GuidelinesScreen extends StatelessWidget {
  const GuidelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZivoPalette.of(context).canvas,
      appBar: AppBar(
        title: Text('Community guidelines', style: AppTextStyles.headingMedium),
        backgroundColor: ZivoPalette.of(context).canvas,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            CommunityGuidelines.title,
            style: AppTextStyles.headingSmall,
          ),
          const Gap(4),
          Text(
            'Version ${CommunityGuidelines.currentVersion}',
            style: AppTextStyles.bodySmall.copyWith(color: ZivoPalette.of(context).textMuted),
          ),
          const Gap(16),
          Text(
            CommunityGuidelines.bodyMd,
            style: AppTextStyles.bodyMedium.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}
