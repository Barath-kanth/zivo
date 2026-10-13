import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/auth/auth_bloc.dart';
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
    return MaterialApp.router(
      title: AppBrand.appTitle,
      debugShowCheckedModeBanner: false,
      routerConfig: _router.config,
      theme: _buildTheme(),
      builder: (context, child) => ZivoLaunch(
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }

  ThemeData _buildTheme() => AppTheme.light;
}
