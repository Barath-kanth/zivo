import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/auth/auth_bloc.dart';
import 'blocs/a11y/a11y_cubit.dart';
import 'core/router/app_router.dart';
import 'core/constants/app_brand.dart';
import 'core/constants/app_colors.dart';
import 'core/constants/app_theme.dart';
import 'ui/_shared/zivo_launch.dart';

class HyperlocalApp extends StatefulWidget {
  const HyperlocalApp({super.key});

  @override
  State<HyperlocalApp> createState() => _HyperlocalAppState();
}

class _HyperlocalAppState extends State<HyperlocalApp> {
  late final AppRouter _router;

  @override
  void initState() {
    super.initState();
    _router = AppRouter(authBloc: context.read<AuthBloc>());

    // Immersive light status bar
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.backgroundDark,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<A11yCubit, bool>(
      builder: (context, a11yOn) {
        return MaterialApp.router(
          title: AppBrand.appTitle,
          debugShowCheckedModeBanner: false,
          routerConfig: _router.config,
          theme: _buildTheme(a11yOn),
          builder: (context, child) {
            final content = ZivoLaunch(
              child: child ?? const SizedBox.shrink(),
            );
            if (!a11yOn) return content;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.18),
              ),
              child: content,
            );
          },
        );
      },
    );
  }

  ThemeData _buildTheme(bool a11yOn) {
    final base = AppTheme.light;
    if (!a11yOn) return base;
    return base.copyWith(
      visualDensity: VisualDensity.comfortable,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 48),
        ),
      ),
    );
  }
}
