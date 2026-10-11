import 'package:akshi/app/providers.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/presentation/monitor_form_screen.dart';
import 'package:akshi/features/tags/application/tag_controller.dart';
import 'package:akshi/features/tags/domain/monitor_tag.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('missing edit id renders not found and never renders a form', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monitorControllerProvider.overrideWith(
            () => _TestMonitorController(const <MonitorEntry>[]),
          ),
          deviceOfflineProvider.overrideWith(
            (ref) => Stream<bool>.value(false),
          ),
        ],
        child: const MaterialApp(
          home: MonitorFormScreen.edit(monitorId: 'missing-monitor'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Monitor not found'), findsOneWidget);
    expect(find.text('Back to monitors'), findsOneWidget);
    expect(find.text('Save changes'), findsNothing);
    expect(find.text('Add monitor'), findsNothing);
    expect(find.byType(Form), findsNothing);
  });

  testWidgets('create mode explains each email role and its limits', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monitorControllerProvider.overrideWith(
            () => _TestMonitorController(const <MonitorEntry>[]),
          ),
          deviceOfflineProvider.overrideWith(
            (ref) => Stream<bool>.value(false),
          ),
          tagControllerProvider.overrideWith(_TestTagController.new),
        ],
        child: const MaterialApp(home: MonitorFormScreen.create()),
      ),
    );
    await tester.pumpAndSettle();

    final emailCheck = find.text('Email configuration');
    await tester.dragUntilVisible(
      emailCheck,
      find.byType(ListView),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    await tester.tap(emailCheck);
    await tester.pumpAndSettle();

    expect(find.text('Sends email from this domain'), findsOneWidget);
    expect(
      find.text(
        'Automatically checks SPF and DMARC. DKIM is checked only for selector names you add below.',
      ),
      findsOneWidget,
    );
    expect(find.text('Receives email at this domain'), findsOneWidget);
    expect(
      find.text('Automatically checks MX, MTA-STS, and TLS reporting records.'),
      findsOneWidget,
    );
    expect(find.textContaining('finds standard mail records'), findsOneWidget);
    expect(
      find.textContaining('selector1._domainkey.example.com'),
      findsOneWidget,
    );

    final sendsToggle = find.text('Sends email from this domain');
    await tester.ensureVisible(sendsToggle);
    await tester.pumpAndSettle();
    await tester.tap(sendsToggle);
    await tester.pumpAndSettle();

    expect(find.text('DKIM selector names (optional)'), findsNothing);
  });
}

class _TestMonitorController extends MonitorController {
  _TestMonitorController(this.monitors);

  final List<MonitorEntry> monitors;

  @override
  Future<List<MonitorEntry>> build() async => monitors;
}

class _TestTagController extends TagController {
  @override
  Future<List<MonitorTag>> build() async => const <MonitorTag>[];
}
