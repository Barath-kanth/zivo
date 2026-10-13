import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/core/constants/app_brand.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/ui/_shared/a11y_widgets.dart';
import 'package:hyperlocal/ui/_shared/zivo_logo.dart';

/// Zevoa-style welcome gate before phone/email login.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, this.returnTo});

  final String? returnTo;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const _pages = <({String title, String body, List<String> icons})>[
    (
      title: 'Welcome to Zivo!',
      body:
          'Trusted help nearby — queues, chores, and care when you need a hand.',
      icons: [
        'assets/icons/3d/bag.png',
        'assets/icons/3d/bucket.png',
        'assets/icons/3d/scooter.png',
      ],
    ),
    (
      title: 'Post in minutes',
      body:
          'Describe the task, see a fair price, and match with a verified helper close by.',
      icons: [
        'assets/icons/3d/camera.png',
        'assets/icons/3d/map-pin.png',
        'assets/icons/3d/money.png',
      ],
    ),
    (
      title: 'Earn as a Helper',
      body:
          'Switch modes anytime, pick jobs in your neighbourhood, and get paid into escrow-safe earnings.',
      icons: [
        'assets/icons/3d/tool.png',
        'assets/icons/3d/wallet.png',
        'assets/icons/3d/trophy.png',
      ],
    ),
  ];

  late final PageController _pageController;
  Timer? _autoSlide;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _autoSlide = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_page + 1) % _pages.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoSlide?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  String? get _returnTo {
    final fromWidget = widget.returnTo;
    if (fromWidget != null && fromWidget.isNotEmpty) return fromWidget;
    return GoRouterState.of(context).uri.queryParameters['returnTo'];
  }

  void _openLogin({required bool signUp}) {
    final returnTo = _returnTo;
    final q = <String, String>{
      if (returnTo != null && returnTo.isNotEmpty) 'returnTo': returnTo,
      if (signUp) 'mode': 'signup',
    };
    final uri =
        Uri(path: AppRoutes.loginForm, queryParameters: q.isEmpty ? null : q);
    context.go(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final slide = _pages[_page];
    final readText =
        '${slide.title}. ${slide.body} Access Your Account to sign in. Signup if you are new.';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Column(
            children: [
              Row(
                children: [
                  const ZivoLogo(size: 34, showWordmark: true),
                  const Spacer(),
                  Material(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('English is the default for now.'),
                          ),
                        );
                      },
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.language_rounded,
                                size: 18, color: AppColors.textSecondary),
                            SizedBox(width: 6),
                            Text(
                              'English',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(10),
              A11yAuthBar(
                readText: readText,
                hint:
                    'Zivo welcome screen. Slide: ${slide.title}. Buttons: Access Your Account, Signup.',
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return _WelcomeSlide(page: page, key: ValueKey(index));
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final active = i == _page;
                  return GestureDetector(
                    onTap: () => _pageController.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 18 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color:
                            active ? Colors.black : const Color(0xFFD9D9D9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                }),
              ),
              const Gap(22),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: () => _openLogin(signUp: false),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Text(
                    'Access Your Account',
                    style: AppTextStyles.buttonLabel.copyWith(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const Gap(16),
              Text.rich(
                TextSpan(
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                  children: [
                    const TextSpan(text: "Don't have an account? "),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: () => _openLogin(signUp: true),
                        child: Text(
                          'Signup',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              Gap(12 + bottom),
              Text(
                AppBrand.tagline,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const Gap(8),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeSlide extends StatelessWidget {
  const _WelcomeSlide({super.key, required this.page});

  final ({String title, String body, List<String> icons}) page;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(flex: 1),
        Expanded(
          flex: 5,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < page.icons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Image.asset(
                      page.icons[i],
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    )
                        .animate(delay: Duration(milliseconds: 80 * i))
                        .fadeIn(duration: 360.ms)
                        .slideX(
                          begin: -0.35,
                          end: 0,
                          curve: Curves.easeOutCubic,
                          duration: 480.ms,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const Gap(20),
        Text(
          page.title,
          textAlign: TextAlign.center,
          style: AppTextStyles.headingLarge.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: Colors.black,
          ),
        ),
        const Gap(10),
        Text(
          page.body,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
            fontSize: 15,
            height: 1.45,
          ),
        ),
        const Spacer(flex: 1),
      ],
    );
  }
}
