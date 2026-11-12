import 'package:flutter_test/flutter_test.dart';
import 'package:safecampus_app/screens/campus_safe_map_screen.dart';

void main() {
  test('satellite link opens the Potsdam campus in Google Maps', () {
    final uri = CampusSafeMapScreen.satelliteMapUri;
    expect(uri.scheme, 'https');
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/@');
    expect(uri.queryParameters, {
      'api': '1',
      'map_action': 'map',
      'center': '-32.9013039,27.664223',
      'zoom': '17',
      'basemap': 'satellite',
    });
  });

  test('reads a safety location with numeric coordinates', () {
    final location = CampusSafetyLocation.fromData({
      'name': ' Security office ',
      'type': 'security_post',
      'description': 'Main entrance',
      'latitude': -32.9013039,
      'longitude': 27.664223,
    });

    expect(location, isNotNull);
    expect(location!.name, 'Security office');
    expect(location.type, 'security post');
    expect(location.description, 'Main entrance');
    expect(location.position.latitude, -32.9013039);
    expect(location.position.longitude, 27.664223);
  });

  test('rejects missing, non-numeric and invalid coordinates', () {
    for (final data in [
      <String, dynamic>{},
      {'latitude': '32', 'longitude': 27},
      {'latitude': 91, 'longitude': 27},
      {'latitude': -32, 'longitude': 181},
      {'latitude': double.nan, 'longitude': 27},
      {'latitude': -32, 'longitude': double.infinity},
    ]) {
      expect(CampusSafetyLocation.fromData(data), isNull);
    }
  });

  test('handles older locations with missing optional details', () {
    final location = CampusSafetyLocation.fromData({
      'latitude': -32,
      'longitude': 27,
    });
    expect(location!.name, 'Safety location');
    expect(location.type, isEmpty);
    expect(location.description, isEmpty);
  });
}
