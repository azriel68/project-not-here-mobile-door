// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:door/app_controller.dart';
import 'package:door/main.dart';

class FakeAppController extends AppController {
  FakeAppController() : super(initialApiBaseUrl: 'https://api.example.test/') {
    email = 'membre@example.test';
  }

  bool didLoadCoworks = false;

  @override
  Future<void> loadCoworks() async {
    didLoadCoworks = true;
    isBusy = true;
    notifyListeners();
    coworkers = const [
      Cowork(
          id: '1',
          name: 'Cowork de test',
          hostname: 'cowork.test',
          frontUrl: 'https://cowork.test/#/')
    ];
    isBusy = false;
    notifyListeners();
  }
}

void main() {
  testWidgets('application starts on the login screen',
      (WidgetTester tester) async {
    final controller = FakeAppController();
    controller.isReady = true;
    await tester.pumpWidget(DollyDeskApp(controller: controller));
    await tester.pump();

    expect(find.text('DollyDesk Door'), findsOneWidget);
    expect(controller.didLoadCoworks, isTrue);
    expect(find.text('Serveur'), findsNothing);
    expect(find.text('ADRESSE DE L\'API'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'membre@example.test',
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/dollydesk_app_icon.png',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Rechercher un cowork'));
    await tester.pumpAndSettle();
    expect(find.text('Choisir un cowork'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Cowork de test');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cowork de test').last);
    await tester.pumpAndSettle();

    expect(controller.selectedCowork?.name, 'Cowork de test');
    expect(tester.takeException(), isNull);
  });
}
