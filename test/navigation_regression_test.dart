import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/ui/_shared/glass_dock.dart';
import 'package:hyperlocal/ui/_shared/shell_route_content.dart';
import 'package:hyperlocal/ui/_shared/zivo_launch.dart';

void main() {
  testWidgets('Account retains a light scrim over dark content', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      backgroundColor: Colors.black,
      extendBody: true,
      body: const ColoredBox(color: Colors.black),
      bottomNavigationBar: GlassDock(child: Row(children: [
        for (final label in ['Home', 'Post', 'Wallet', 'Account'])
          Expanded(child: TextButton(onPressed: () {}, child: Text(label))),
        const SizedBox(width: 56),
      ])),
    )));
    expect(find.text('Account'), findsOneWidget);
    final scrim = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('glass-dock-scrim')),
    );
    // Even on black, the actual separately painted scrim must remain light.
    final composite = Color.alphaBlend(scrim.color, Colors.black);
    expect(composite.computeLuminance(), greaterThan(0.65));
    await tester.tap(find.text('Account'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shell navigator survives rapid Home Account Wallet changes',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          navigatorKey: navigatorKey,
          builder: (context, state, child) => Scaffold(
            body: ShellRouteContent(
              isHome: state.uri.path == '/',
              routedChild: child,
              home: const Center(child: Text('Client home')),
            ),
          ),
          routes: [
            GoRoute(path: '/', builder: (_, __) => const SizedBox.shrink()),
            GoRoute(path: '/account', builder: (_, __) =>
              const Center(child: Text('Account page'))),
            GoRoute(path: '/wallet', builder: (_, __) =>
              const Center(child: Text('Wallet page'))),
          ],
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => ZivoLaunch(child: child!),
    ));
    final originalNavigator = navigatorKey.currentState;
    expect(originalNavigator, isNotNull);
    // Change routes during launch and while earlier page transitions run.
    for (final route in ['/account', '/wallet', '/', '/wallet', '/account', '/']) {
      router.go(route);
      await tester.pump(const Duration(milliseconds: 30));
      expect(navigatorKey.currentState, same(originalNavigator));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(find.text('Client home'), findsOneWidget);
    router.go('/account');
    await tester.pumpAndSettle();
    expect(find.text('Account page'), findsOneWidget);
    expect(navigatorKey.currentState, same(originalNavigator));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    expect(tester.takeException(), isNull);
  });
}
