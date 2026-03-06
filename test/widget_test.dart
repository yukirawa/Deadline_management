import 'package:flutter_test/flutter_test.dart';
import 'package:kigenkanri/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('アプリタイトルが表示される', (WidgetTester tester) async {
    await tester.pumpWidget(const DeadlineRadarApp());
    await tester.pumpAndSettle();

    expect(find.text('締切レーダー'), findsOneWidget);
  });
}
