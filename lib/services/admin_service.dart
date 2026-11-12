import 'package:cloud_firestore/cloud_firestore.dart';

class AdminService {
  AdminService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchUsers() {
    return _firestore.collection('users').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchIncidents() {
    return _firestore
        .collection('incidents')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchHelplines() {
    return _firestore
        .collection('campus_settings')
        .doc('helplines')
        .snapshots();
  }

  Future<void> approveStaff(String uid, String adminUid) async {
    await _firestore.collection('users').doc(uid).update({
      'accountStatus': 'active',
      'role': 'campus_security',
      'approvedBy': adminUid,
      'approvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setAccountStatus({
    required String uid,
    required String status,
  }) async {
    if (!const {'active', 'suspended', 'inactive'}.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Unsupported account status');
    }
    await _firestore.collection('users').doc(uid).update({
      'accountStatus': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveHelplines(List<Map<String, String>> contacts) {
    return _firestore.collection('campus_settings').doc('helplines').set({
      'contacts': contacts,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

}
