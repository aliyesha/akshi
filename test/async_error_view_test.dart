import 'package:akshi/core/widgets/async_error_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('shows a safe retryable load failure', (tester) async {
    var retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AsyncErrorView(onRetry: () => retryCount += 1)),
      ),
    );

    expect(
      find.text('Akshi couldn’t load this information. Please try again.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Try again'));

    expect(retryCount, 1);
  });
}
