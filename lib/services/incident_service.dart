import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class IncidentService {
  IncidentService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<void> createSosAlert(Position position) async {
    final user = _requireSignedInUser();
    final profile = await _getStudentProfile(user);
    await _createIncident({
      ...profile,
      'userId': user.uid,
      'userEmail': user.email,
      'reportType': 'sos',
      'category': 'Emergency SOS',
      'description': 'Student triggered an emergency SOS alert.',
      'location': 'GPS location',
      'latitude': position.latitude,
      'longitude': position.longitude,
      'recipientTeams': const ['campus_security'],
      'status': 'pending',
    });
  }

  Future<void> submitIncident({
    required String category,
    required String location,
    required String description,
  }) async {
    final user = _requireSignedInUser();
    final profile = await _getStudentProfile(user);
    await _createIncident({
      ...profile,
      'userId': user.uid,
      'userEmail': user.email,
      'reportType': 'incident',
      'category': category,
      'location': location.trim(),
      'description': description.trim(),
      'recipientTeams': _recipientTeamsFor(category),
      'status': 'pending',
    });
  }

  // Campus security verifies every report first and escalates (for example,
  // calling an ambulance) when needed.
  List<String> _recipientTeamsFor(String category) => const ['campus_security'];

  Future<Map<String, dynamic>> _getStudentProfile(User user) async {
    final snapshot = await _firestore.collection('users').doc(user.uid).get();
    final profile = snapshot.data() ?? <String, dynamic>{};
    return {
      'studentNumber': user.email?.split('@').first ?? '',
      'studentName': profile['fullName'] ?? user.displayName ?? '',
      'studentPhone': profile['phoneNumber'] ?? '',
      'campus': profile['campus'] ?? '',
      'residenceBlock': profile['residenceBlock'] ?? '',
      'room': profile['room'] ?? '',
      'emergencyContacts': profile['emergencyContacts'] ?? <Map<String, dynamic>>[],
    };
  }

  Future<void> _createIncident(Map<String, dynamic> data) {
    return _firestore.collection('incidents').add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyIncidents(String userId) {
    return _firestore
        .collection('incidents')
        .where('userId', isEqualTo: userId)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchTeamIncidents(String team) {
    final collection = _firestore.collection('incidents');
    if (team == 'admin') return collection.snapshots();
    return collection.where('recipientTeams', arrayContains: team).snapshots();
  }

  Future<void> advanceStatus({
    required String incidentId,
    required String currentStatus,
    required String nextStatus,
    required String responderId,
  }) async {
    const transitions = {
      'pending': {'acknowledged'},
      'acknowledged': {'dispatched', 'resolved'},
      'dispatched': {'resolved'},
    };
    if (!transitions[currentStatus]!.contains(nextStatus)) {
      throw StateError('That incident status transition is not allowed.');
    }

    final timestamp = FieldValue.serverTimestamp();
    final update = <String, dynamic>{
      'status': nextStatus,
      'updatedAt': timestamp,
    };
    switch (nextStatus) {
      case 'acknowledged':
        update['acknowledgedBy'] = responderId;
        update['acknowledgedAt'] = timestamp;
        break;
      case 'dispatched':
        update['dispatchedBy'] = responderId;
        update['dispatchedAt'] = timestamp;
        break;
      case 'resolved':
        update['resolvedBy'] = responderId;
        update['resolvedAt'] = timestamp;
        break;
    }

    await _firestore.collection('incidents').doc(incidentId).update(update);
  }

  User _requireSignedInUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before submitting an incident.');
    }
    return user;
  }
}
