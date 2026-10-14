import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal/core/constants/app_theme.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/ui/_shared/helper_job_search.dart';
import 'package:hyperlocal/ui/_shared/mode_cover_banner.dart';
import 'package:hyperlocal/ui/_shared/empty_state_widget.dart';

void main() {
  testWidgets(
    'both role headers remain usable on narrow screens at 200% text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final helper in [false, true]) {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 780),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: ModeCoverBanner(
                    isHelper: helper,
                    onModeTap: () {},
                    onSearchTap: () => taps++,
                    searchHint: 'Search services',
                    trailing: const Icon(Icons.person_outline),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Search services'));
        expect(taps, 1);
      }
    },
  );

  testWidgets('empty states stay scrollable in a short viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SizedBox(
            height: 160,
            child: EmptyStateWidget(
              icon: Icons.search,
              title: 'No matching jobs',
              subtitle: 'Try another service or clear filters.',
              color: Colors.green,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  test('helper discovery searches task, service and area together', () {
    final task = Task.fromJson({
      'id': 'test-task',
      'client_id': 'test-client',
      'title': 'Weekly groceries',
      'description': 'Collect vegetables and rice',
      'category': 'groceryRun',
      'location_label': 'Jaffna',
      'status': 'open',
      'created_at': '2026-10-13T10:00:00Z',
    });
    expect(HelperJobSearch.matches(task, 'rice jaffna'), isTrue);
    expect(HelperJobSearch.matches(task, 'weekly'), isTrue);
    expect(HelperJobSearch.matches(task, 'painting'), isFalse);
  });
}
