import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:akshi/core/widgets/akshi_notice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final themes = <String, ThemeData>{
    'light': AkshiTheme.light,
    'dark': AkshiTheme.dark,
  };

  for (final theme in themes.entries) {
    for (final tone in AkshiNoticeTone.values) {
      testWidgets('${theme.key} ${tone.name} notice uses the shared duration', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.value,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showAkshiNotice(
                    context,
                    title: 'Notice title',
                    message: 'Notice message',
                    tone: tone,
                  ),
                  child: const Text('Show notice'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show notice'));
        await tester.pump();

        expect(find.text('Notice title'), findsOneWidget);
        expect(find.text('Notice message'), findsOneWidget);
        expect(
          tester.widget<SnackBar>(find.byType(SnackBar)).duration,
          const Duration(seconds: 6),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
