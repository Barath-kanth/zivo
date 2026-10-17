import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal/blocs/a11y/a11y_cubit.dart';
import 'package:hyperlocal/blocs/ability/ability_cubit.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/ui/accessibility/ability_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(AbilityCubit, List<AbilityProfile>)> pump(WidgetTester tester) async {
    final synced = <AbilityProfile>[];
    final cubit = AbilityCubit(onChanged: (p) async => synced.add(p));
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<LocaleCubit>(create: (_) => LocaleCubit()),
          BlocProvider<A11yCubit>(create: (_) => A11yCubit()),
          BlocProvider<AbilityCubit>.value(value: cubit),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AbilityPicker(closeSheet: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    return (cubit, synced);
  }

  testWidgets('no ability selected → no tools, nothing disclosed', (tester) async {
    await pump(tester);
    expect(find.text('How should Zivo adapt to you?'), findsOneWidget);
    expect(find.text('Zivo Eyes'), findsNothing);
    expect(find.text('Doorstep Talk'), findsNothing);
    expect(find.text('Tell clients about my access needs'), findsNothing);
  });

  testWidgets('each ability unlocks its own AI tool and syncs to the server', (tester) async {
    final (cubit, synced) = await pump(tester);

    await tester.tap(find.text('Blind / low vision'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Zivo Eyes'), findsOneWidget);
    expect(find.text('Doorstep Talk'), findsNothing);
    expect(cubit.state.has('visual'), isTrue);

    await tester.tap(find.text('Deaf / hard of hearing'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Doorstep Talk'), findsOneWidget);
    expect(find.text('Say it for me'), findsOneWidget);

    // Disclosure is opt-in and OFF by default.
    expect(find.text('Tell clients about my access needs'), findsOneWidget);
    expect(cubit.state.disclose, isFalse);
    expect(synced.last.abilities, {'visual', 'hearing'});
    expect(synced.last.disclose, isFalse);

    // Unselecting everything removes tools and forces disclosure off.
    await cubit.setDisclose(true);
    await tester.tap(find.text('Blind / low vision'));
    await tester.tap(find.text('Deaf / hard of hearing'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Zivo Eyes'), findsNothing);
    expect(cubit.state.disclose, isFalse);
  });
}
