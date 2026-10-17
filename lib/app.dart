import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'blocs/auth/auth_bloc.dart';
import 'blocs/a11y/a11y_cubit.dart';
import 'blocs/theme/theme_cubit.dart';
import 'core/l10n/locale_cubit.dart';
import 'core/router/app_router.dart';
import 'core/constants/app_brand.dart';
import 'core/constants/app_theme.dart';
import 'core/constants/zivo_palette.dart';
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
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  void _syncSystemUi(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final canvas =
        dark ? ZivoPalette.dark.canvas : ZivoPalette.light.canvas;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: canvas,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // IMPORTANT: Do not bind MaterialApp.locale to ta/si/hi/… —
    // Flutter's MaterialLocalizations do not cover those codes and the
    // whole tree goes blank (white overlay). App copy uses LocaleCubit.
    return BlocBuilder<ThemeCubit, ThemeMode>(
      builder: (context, themeMode) {
        return BlocBuilder<A11yCubit, bool>(
          builder: (context, a11yOn) {
            return MaterialApp.router(
              title: AppBrand.appTitle,
              debugShowCheckedModeBanner: false,
              routerConfig: _router.config,
              locale: const Locale('en'),
              supportedLocales: const [Locale('en')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: _withA11y(AppTheme.light, a11yOn),
              darkTheme: _withA11y(AppTheme.dark, a11yOn),
              themeMode: themeMode,
              builder: (context, child) {
                final brightness = Theme.of(context).brightness;
                _syncSystemUi(brightness);
                final canvas = ZivoPalette.of(context).canvas;
                return BlocBuilder<LocaleCubit, Locale>(
                  builder: (context, appLocale) {
                    final content = ZivoLaunch(
                      child: child ?? const SizedBox.shrink(),
                    );
                    final directed = Directionality(
                      textDirection: appLocale.languageCode == 'ar'
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: content,
                    );
                    // Language must never magnify the UI. Keep system scale at 1.0;
                    // Accessibility mode may bump text slightly (capped).
                    final scaler = a11yOn
                        ? const TextScaler.linear(1.12)
                        : TextScaler.noScaling;
                    return ColoredBox(
                      color: canvas,
                      child: MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: scaler),
                        child: directed,
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  ThemeData _withA11y(ThemeData base, bool a11yOn) {
    if (!a11yOn) return base;
    return base.copyWith(visualDensity: VisualDensity.standard);
  }
}
