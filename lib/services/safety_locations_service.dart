import 'package:cloud_firestore/cloud_firestore.dart';

class SafetyLocation {
  const SafetyLocation({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;

  factory SafetyLocation.fromData(Map<String, dynamic> data) {
    final id = data['id'];
    final name = data['name'];
    final description = data['description'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        description is! String ||
        description.trim().isEmpty) {
      throw const FormatException('Invalid safety location data.');
    }
    return SafetyLocation(id: id, name: name, description: description);
  }

  Map<String, String> toData() => {
    'id': id,
    'name': name,
    'description': description,
  };
}

class SafetyLocationsService {
  SafetyLocationsService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _reference =>
      _firestore.collection('campus_settings').doc('safety_locations');

  static List<SafetyLocation> parse(Map<String, dynamic>? data) {
    if (data == null) return [];
    final values = data['locations'];
    if (values is! List) {
      throw const FormatException('Invalid safety locations list.');
    }
    return values.map((value) {
      if (value is! Map) {
        throw const FormatException('Invalid safety location data.');
      }
      return SafetyLocation.fromData(Map<String, dynamic>.from(value));
    }).toList();
  }

  Stream<List<SafetyLocation>> watch() =>
      _reference.snapshots().map((snapshot) => parse(snapshot.data()));

  Future<void> save({
    String? id,
    required String name,
    required String description,
  }) async {
    final cleanName = name.trim();
    final cleanDescription = description.trim();
    if (cleanName.isEmpty || cleanDescription.isEmpty) {
      throw ArgumentError('A name and description are required.');
    }
    final locationId = id ?? _firestore.collection('campus_settings').doc().id;
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(_reference);
      final locations = parse(snapshot.data());
      final index = locations.indexWhere(
        (location) => location.id == locationId,
      );
      final location = SafetyLocation(
        id: locationId,
        name: cleanName,
        description: cleanDescription,
      );
      if (id == null) {
        locations.add(location);
      } else if (index >= 0) {
        locations[index] = location;
      } else {
        throw StateError('This location no longer exists.');
      }
      transaction.set(_reference, {
        'locations': locations.map((location) => location.toData()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> delete(String id) async {
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(_reference);
      final locations = parse(snapshot.data());
      final index = locations.indexWhere((location) => location.id == id);
      if (index < 0) throw StateError('This location no longer exists.');
      locations.removeAt(index);
      transaction.set(_reference, {
        'locations': locations.map((location) => location.toData()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
