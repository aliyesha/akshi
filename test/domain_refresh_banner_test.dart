import 'package:akshi/features/domains/application/domain_controller.dart';
import 'package:akshi/features/domains/presentation/widgets/domain_refresh_banner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('shows progress and explains that saved results remain visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          domainRefreshProvider.overrideWith(_RunningRefreshController.new),
        ],
        child: const MaterialApp(home: Scaffold(body: DomainRefreshBanner())),
      ),
    );

    expect(find.text('Refreshing domains - 1 of 3 checked'), findsOneWidget);
    expect(find.textContaining('Showing results saved'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('animates while waiting for the first completed domain', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          domainRefreshProvider.overrideWith(_PreparingRefreshController.new),
        ],
        child: const MaterialApp(home: Scaffold(body: DomainRefreshBanner())),
      ),
    );

    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, isNull);
    expect(find.text('Refreshing domains - 0 of 3 checked'), findsOneWidget);
  });

  testWidgets('explains finalization after every domain finishes', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          domainRefreshProvider.overrideWith(_FinalizingRefreshController.new),
        ],
        child: const MaterialApp(home: Scaffold(body: DomainRefreshBanner())),
      ),
    );

    expect(find.text('Saving refreshed results'), findsOneWidget);
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, isNull);
  });

  testWidgets('keeps a sanitized failed refresh outcome visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          domainRefreshProvider.overrideWith(_FailedRefreshController.new),
        ],
        child: const MaterialApp(home: Scaffold(body: DomainRefreshBanner())),
      ),
    );

    expect(find.text('Refresh could not finish'), findsOneWidget);
    expect(find.textContaining('Saved results remain visible'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('takes no space while refresh is idle', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: DomainRefreshBanner())),
      ),
    );

    expect(find.textContaining('Refreshing domains'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}

class _RunningRefreshController extends DomainRefreshController {
  @override
  DomainRefreshState build() => DomainRefreshState.running(
    startedAt: DateTime.utc(2026, 6, 14, 10),
    completed: 1,
    total: 3,
    lastCompletedAt: DateTime.utc(2026, 6, 14, 9),
  );
}

class _PreparingRefreshController extends DomainRefreshController {
  @override
  DomainRefreshState build() => DomainRefreshState.running(
    startedAt: DateTime.utc(2026, 6, 14, 10),
    completed: 0,
    total: 3,
  );
}

class _FinalizingRefreshController extends DomainRefreshController {
  @override
  DomainRefreshState build() => DomainRefreshState.running(
    startedAt: DateTime.utc(2026, 6, 14, 10),
    completed: 3,
    total: 3,
  );
}

class _FailedRefreshController extends DomainRefreshController {
  @override
  DomainRefreshState build() => DomainRefreshState.idle(
    lastCompletedAt: DateTime.utc(2026, 6, 14, 9),
    lastFailedAt: DateTime.utc(2026, 6, 14, 10),
  );
}
