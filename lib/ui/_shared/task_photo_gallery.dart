import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';

/// Horizontal gallery of client-uploaded task reference photos.
class TaskPhotoGallery extends StatelessWidget {
  const TaskPhotoGallery({
    super.key,
    required this.photoUrls,
    this.height = 96,
    this.label = 'Client photos',
  });

  final List<String> photoUrls;
  final double height;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (photoUrls.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.capsLabel.copyWith(
            color: AppColors.textMuted,
            fontSize: 10,
          ),
        ),
        const Gap(8),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photoUrls.length,
            separatorBuilder: (_, __) => const Gap(8),
            itemBuilder: (context, i) {
              final url = photoUrls[i];
              return GestureDetector(
                onTap: () => _openFull(context, url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.cardElevated,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textMuted,
                        ),
                      ),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: AppColors.cardElevated,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openFull(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
