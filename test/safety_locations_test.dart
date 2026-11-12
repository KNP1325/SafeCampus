import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safecampus_app/screens/safety_location_dialog.dart';
import 'package:safecampus_app/services/safety_locations_service.dart';

void main() {
  test('reads and preserves location details', () {
    final locations = SafetyLocationsService.parse({
      'locations': [
        {
          'id': 'clinic',
          'name': 'Campus Clinic',
          'description': 'Opposite the Sports Office.',
        },
      ],
    });
    expect(locations.single.toData(), {
      'id': 'clinic',
      'name': 'Campus Clinic',
      'description': 'Opposite the Sports Office.',
    });
    expect(SafetyLocationsService.parse(null), isEmpty);
  });

  test('reports invalid location data instead of hiding it', () {
    expect(
      () => SafetyLocationsService.parse({'locations': 'bad'}),
      throwsFormatException,
    );
    expect(
      () => SafetyLocationsService.parse({
        'locations': [
          {'id': 'x'},
        ],
      }),
      throwsFormatException,
    );
  });

  testWidgets('requires a name and description', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SafetyLocationDialog()));
    await tester.tap(find.text('SAVE'));
    await tester.pump();
    expect(find.text('Enter a name.'), findsOneWidget);
    expect(find.text('Enter a description.'), findsOneWidget);
  });
}
