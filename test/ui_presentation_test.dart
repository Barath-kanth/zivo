import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/ui/_shared/category_icon.dart';
import 'package:hyperlocal/ui/_shared/glass_dock.dart';
import 'package:hyperlocal/ui/_shared/zivo_launch.dart';

Widget host(Widget child, {bool reduceMotion = false, bool highContrast = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        disableAnimations: reduceMotion,
        highContrast: highContrast,
      ),
      child: child,
    ),
  );
}

void main() {
  testWidgets('launch blocks hidden controls then releases them without remounting',
      (tester) async {
    var taps = 0;
    final key = GlobalKey();
    final page = Scaffold(
      key: key,
      body: Center(child: TextButton(
        onPressed: () => taps++, child: const Text('Open task'),
      )),
    );
    await tester.pumpWidget(host(ZivoLaunch(child: page)));
    final originalState = key.currentState;
    expect(find.byKey(const ValueKey('zivo-launch-overlay')), findsOneWidget);
    await tester.tap(find.text('Open task'), warnIfMissed: false);
    expect(taps, 0);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('zivo-launch-overlay')), findsNothing);
    expect(key.currentState, same(originalState));
    await tester.tap(find.text('Open task'));
    expect(taps, 1);
    // Parent rebuilds must not replay the launch sequence.
    await tester.pumpWidget(host(ZivoLaunch(child: page)));
    expect(find.byKey(const ValueKey('zivo-launch-overlay')), findsNothing);
  });

  testWidgets('reduced motion skips launch immediately', (tester) async {
    await tester.pumpWidget(host(
      const ZivoLaunch(child: Scaffold(body: Text('Ready'))),
      reduceMotion: true,
    ));
    expect(find.byKey(const ValueKey('zivo-launch-overlay')), findsNothing);
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('launch can be disposed while animation is running', (tester) async {
    await tester.pumpWidget(host(
      const ZivoLaunch(child: Scaffold()),
    ));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass is blurred normally and opaque in high contrast', (tester) async {
    const dock = Scaffold(bottomNavigationBar: GlassDock(
      child: SizedBox(height: 56, child: Text('Navigation')),
    ));
    await tester.pumpWidget(host(dock));
    expect(find.byType(BackdropFilter), findsOneWidget);
    await tester.pumpWidget(host(dock, highContrast: true));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Navigation'), findsOneWidget);
  });

  testWidgets('category badges render bundled 3d icon assets', (tester) async {
    await tester.pumpWidget(host(
      Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: TaskCategory.values
                .map((c) => CategoryIconBadge(c, size: 40))
                .toList(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(TaskCategory.values.length));
  });
}
