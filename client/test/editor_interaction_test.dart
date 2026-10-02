import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pactick/core/dialogs/plan_block_editor.dart';
import 'package:pactick/core/dialogs/project_editor.dart';
import 'package:pactick/core/dialogs/task_editor.dart';
import 'package:pactick/core/state/app_controller.dart';
import 'package:pactick/core/state/app_scope.dart';
import 'package:pactick/core/state/session_scope.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:pactick/data/platform/focus_platform_gateway.dart';
import 'package:pactick/data/repositories/workspace_repository.dart';
import 'package:pactick/features/settings/pages/local_data_settings.dart';

import 'support/session_test_support.dart';

void main() {
  for (final editor in ['任务', '项目', '计划']) {
    testWidgets(
      '$editor draft survives close, back, barrier and window resize',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(412, 915);
        addTearDown(tester.view.reset);
        final app = AppController(
          repository: WorkspaceRepository(MemoryDocumentStore()),
          focusPlatform: const FocusPlatformGateway(),
        );
        await app.initialize();
        addTearDown(app.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () {
                    switch (editor) {
                      case '任务':
                        showTaskEditor(context, controller: app);
                      case '项目':
                        showProjectEditor(context, controller: app);
                      case '计划':
                        showPlanBlockEditor(context, controller: app);
                    }
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, '尚未保存的输入');
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
        expect(find.text('放弃未保存的修改？'), findsOneWidget);
        await tester.tap(find.text('继续编辑'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).first)
              .controller!
              .text,
          '尚未保存的输入',
        );

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('放弃未保存的修改？'), findsOneWidget);
        await tester.tap(find.text('继续编辑'));
        await tester.pumpAndSettle();

        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        expect(find.text('放弃未保存的修改？'), findsOneWidget);
        await tester.tap(find.text('继续编辑'));
        await tester.pumpAndSettle();

        tester.view.physicalSize = const Size(1024, 640);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).first)
              .controller!
              .text,
          '尚未保存的输入',
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('放弃修改'));
        await tester.pumpAndSettle();
        expect(app.tasks, isEmpty);
        expect(app.projects, isEmpty);
        expect(app.planBlocks, isEmpty);
        expect(find.byType(TextFormField), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'server deletion stays open while pending and retains failed input',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);
      final deletion = Completer<http.Response>();
      var requests = 0;
      final session = await createAuthenticatedSessionController(
        client: MockClient((request) async {
          if (request.method == 'DELETE') {
            requests++;
            return deletion.future;
          }
          return http.Response(
            jsonEncode(testAuthSession().toJson()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final app = AppController(
        repository: WorkspaceRepository(MemoryDocumentStore()),
        focusPlatform: const FocusPlatformGateway(),
      );
      await app.initialize();
      var disposed = false;
      addTearDown(() {
        if (!disposed) {
          session.dispose();
          app.dispose();
        }
      });
      await tester.pumpWidget(
        AppScope(
          controller: app,
          child: SessionScope(
            controller: session,
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(child: LocalDataCard()),
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('删除服务器账户'));
      await tester.tap(find.text('删除服务器账户'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '保留的密码');
      await tester.enterText(find.byType(TextFormField).last, 'DELETE');
      await tester.tap(find.text('永久删除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(requests, 1);
      expect(find.text('正在删除…'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('放弃未保存的修改？'), findsNothing);
      deletion.complete(
        http.Response(
          '{"message":"网络请求失败"}',
          503,
          headers: {'content-type': 'application/json'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('保留的密码'), findsOneWidget);
      expect(find.text('DELETE'), findsOneWidget);
      expect(find.textContaining('删除未完成'), findsOneWidget);
      expect(session.isAuthenticated, isTrue);
      expect(requests, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '永久删除'))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      session.dispose();
      app.dispose();
      disposed = true;
    },
  );
}
