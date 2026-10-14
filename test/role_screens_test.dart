import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/task/task_bloc.dart';
import 'package:hyperlocal/core/constants/app_theme.dart';
import 'package:hyperlocal/core/services/gcp/subscription_handle.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/models/user_profile.dart';
import 'package:hyperlocal/data/repositories/auth_repository.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/ui/client/client_home_screen.dart';
import 'package:hyperlocal/ui/helper/helper_home_screen.dart';

class _AuthRepository extends Fake implements AuthRepository {}

class _Auth extends AuthBloc {
  _Auth() : super(authRepository: _AuthRepository()) {
    emit(
      const AuthAuthenticated(
        UserProfile(
          id: 'preview-user',
          fullName: 'Alex',
          isHelperActive: true,
          walletBalance: 2500,
          helperEarnings: 12400,
          totalTasksHelped: 12,
          ratingAsHelper: 4.8,
        ),
      ),
    );
  }
}

class _Tasks extends Fake implements TaskRepository {
  @override
  Future<List<Task>> getClientTasks(String clientId) async => [];
  @override
  Future<List<Task>> getNearbyOpenTasks() async => [
    Task.fromJson({
      'id': 'preview-job',
      'client_id': 'another-client',
      'title': 'Help with weekly groceries',
      'description': 'Collect a small grocery order and bring it to my home.',
      'category': 'groceryRun',
      'status': 'open',
      'location_label': 'Jaffna',
      'estimated_hours': 1,
      'total_amount': 1500,
      'created_at': '2026-10-13T10:00:00Z',
    }),
  ];
  @override
  Future<Map<String, dynamic>> helperBatchRoute() async => {'active_tasks': []};
  @override
  Future<Map<String, dynamic>> helperTrust(String id) async => {
    'vouch_count': 2,
    'vouch_threshold': 3,
  };
  @override
  SubscriptionHandle subscribeToOpenTasks({
    required void Function(Map<String, dynamic>) onInsert,
    required void Function(Map<String, dynamic>) onUpdate,
    required void Function(Map<String, dynamic>) onDelete,
  }) => SubscriptionHandle(() {});
  @override
  void unsubscribe(SubscriptionHandle channel) => channel.cancel();
}

void main() {
  testWidgets(
    'client and helper render and helper search filters the live list',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = FontLoader('Inter')
        ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
      await font.load();
      for (final helper in [false, true]) {
        final auth = _Auth();
        final repo = _Tasks();
        final tasks = TaskBloc(taskRepository: repo);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepositoryProvider<TaskRepository>.value(
            value: repo,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthBloc>.value(value: auth),
                BlocProvider<TaskBloc>.value(value: tasks),
              ],
              child: RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                  theme: AppTheme.light,
                  home: helper
                      ? const HelperHomeScreen()
                      : const ClientHomeScreen(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_UI')) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = Directory('ui-previews')
              ..createSync(recursive: true);
            await File(
              '${directory.path}/${helper ? 'helper' : 'client'}-home.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        if (helper) {
          await tester.tap(find.text('Search jobs near you'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'weekly groceries');
          await tester.pumpAndSettle();
          expect(find.text('Help with weekly groceries'), findsOneWidget);
          await tester.tap(find.text('Help with weekly groceries'));
          await tester.pumpAndSettle();
          expect(find.byType(InputChip), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tasks.close();
        await auth.close();
      }
    },
  );
}
