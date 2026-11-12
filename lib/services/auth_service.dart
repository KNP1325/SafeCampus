import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<String> _reserveStaffNumber(String uid) async {
    final random = Random.secure();
    for (var attempt = 0; attempt < 15; attempt++) {
      final number = (900000000 + random.nextInt(100000000)).toString();
      try {
        // Rules only allow creating a reservation, so a taken number is
        // rejected and we try another one.
        await _firestore.collection('staff_numbers').doc(number).set({
          'uid': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return number;
      } on FirebaseException catch (error) {
        if (error.code != 'permission-denied') rethrow;
      }
    }
    throw StateError('Could not generate a unique staff number. Try again.');
  }

  Future<({UserCredential credential, String? staffNumber})> createAccount({
    required String firstName,
    required String surname,
    required String email,
    required String password,
    String accountType = 'student',
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final credential = await _auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw StateError('Firebase Authentication did not return a user.');
    }

    final staffNumber = accountType == 'student'
        ? null
        : await _reserveStaffNumber(user.uid);
    final fullName = '${firstName.trim()} ${surname.trim()}';
    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'firstName': firstName.trim(),
      'surname': surname.trim(),
      'fullName': fullName,
      'email': normalizedEmail,
      'accountType': accountType,
      if (accountType == 'student')
        'studentNumber': normalizedEmail.split('@').first,
      if (staffNumber != null) 'staffNumber': staffNumber,
      'accountStatus': 'pending',
      'isVerified': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await user.sendEmailVerification();
    await _auth.signOut();
    return (credential: credential, staffNumber: staffNumber);
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() => _auth.signOut();
}
