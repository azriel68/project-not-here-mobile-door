import 'package:door/app_controller.dart';
import 'package:door/door_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDoorController extends AppController {
  FakeDoorController(this.access)
      : super(initialApiBaseUrl: 'https://api.example.test/') {
    user = {
      'firstname': 'Camille',
      'lastname': 'Martin',
      'email': 'camille@example.test'
    };
  }

  final DoorAccess access;
  final commands = <String>[];

  @override
  Future<DoorAccess> loadDoors() async => access;

  @override
  Future<void> setDoor(int id,
      {required bool open,
      required double latitude,
      required double longitude}) async {
    commands.add('$id:${open ? 'open' : 'close'}');
  }
}

Future<void> pumpDoors(
    WidgetTester tester, FakeDoorController controller) async {
  await tester.pumpWidget(MaterialApp(
      home:
          DoorScreen(controller: controller, coordinates: () async => [0, 0])));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one door shows two buttons', (tester) async {
    final controller = FakeDoorController(const DoorAccess(
        doors: [Door(id: 1, label: 'Entrée')], canOpen: true, canClose: true));
    await pumpDoors(tester, controller);

    expect(find.text('Entrée'), findsOneWidget);
    expect(find.text('Bonjour Camille,'), findsOneWidget);
    expect(find.text('Camille Martin · camille@example.test'), findsOneWidget);
    expect(find.text('Ouvrir'), findsOneWidget);
    expect(find.text('Fermer'), findsOneWidget);
    final size = tester.getSize(find.byKey(const ValueKey('open-1')));
    expect(size.height, inInclusiveRange(80, 100));

    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    expect(controller.commands, ['1:open', '1:close']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('several doors show a pair of buttons each', (tester) async {
    final controller = FakeDoorController(const DoorAccess(doors: [
      Door(id: 1, label: 'Entrée'),
      Door(id: 2, label: 'Salle A', roomId: '10'),
    ], canOpen: false, canClose: true));
    await pumpDoors(tester, controller);

    expect(find.text('Ouvrir'), findsNWidgets(2));
    expect(find.text('Fermer'), findsNWidgets(2));
    // Opening is outside the allowed time range: the button does nothing.
    await tester.tap(find.byKey(const ValueKey('open-2')));
    await tester.pumpAndSettle();
    expect(controller.commands, isEmpty);

    await tester.tap(find.byKey(const ValueKey('close-2')));
    await tester.pumpAndSettle();
    expect(controller.commands, ['2:close']);
  });

  testWidgets('no door shows an empty state', (tester) async {
    await pumpDoors(
        tester,
        FakeDoorController(
            const DoorAccess(doors: [], canOpen: true, canClose: true)));
    expect(find.text('Aucune porte accessible'), findsOneWidget);
  });
}
