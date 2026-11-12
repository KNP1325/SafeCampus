import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class ResponderNotificationService {
  ResponderNotificationService._();

  static final ResponderNotificationService instance =
      ResponderNotificationService._();

  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _registeredUid;
  String? _registeredRole;

  static const _responderRoles = {
    'campus_security',
    'medical_services',
    'fire_services',
    'student_welfare',
    'admin',
  };

  Future<bool> registerCurrentDevice() async {
    if (kIsWeb ||
        !{
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(defaultTargetPlatform)) {
      return false;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final tokenResult = await user.getIdTokenResult(true);
    final role = tokenResult.claims?['role'];
    final isAdmin = tokenResult.claims?['admin'] == true;
    var authorizedRole = role is String && _responderRoles.contains(role)
        ? role
        : isAdmin
        ? 'admin'
        : null;
    if (authorizedRole == null) {
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = profile.data();
      if (data?['role'] == 'campus_security' &&
          data?['accountStatus'] == 'active') {
        authorizedRole = 'campus_security';
      }
    }

    final permission = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      throw StateError(
        'Notification permission is turned off. Enable it in your phone settings to receive responder alerts.',
      );
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) {
      throw StateError('Firebase Messaging did not provide a device token.');
    }

    await _saveUserToken(uid: user.uid, token: token);
    if (authorizedRole != null) {
      await _saveResponderToken(
        uid: user.uid,
        role: authorizedRole,
        token: token,
      );
    }
    await _tokenRefreshSubscription?.cancel();
    _registeredUid = user.uid;
    _registeredRole = authorizedRole;
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
        .listen(
          (refreshedToken) async {
            try {
              await _saveUserToken(uid: user.uid, token: refreshedToken);
              if (authorizedRole != null) {
                await _saveResponderToken(
                  uid: user.uid,
                  role: authorizedRole,
                  token: refreshedToken,
                );
              }
            } catch (error) {
                debugPrint(
                  'Could not update SafeCampus notification token: $error',
                );
            }
          },
          onError: (Object error) {
            debugPrint('SafeCampus responder token refresh failed: $error');
          },
        );
    return true;
  }

  Future<void> unregisterCurrentDevice() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;

    final uid = _registeredUid;
    final role = _registeredRole;
    _registeredUid = null;
    _registeredRole = null;
    if (uid == null) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('user_tokens')
          .doc(uid)
          .collection('devices')
          .doc(token)
          .delete();
      if (role != null) {
        await FirebaseFirestore.instance
            .collection('staff_tokens')
            .doc(uid)
            .collection('devices')
            .doc(token)
            .delete();
      }
      await FirebaseMessaging.instance.deleteToken();
    }
  }

  Future<void> _saveUserToken({
    required String uid,
    required String token,
  }) {
    return FirebaseFirestore.instance
        .collection('user_tokens')
        .doc(uid)
        .collection('devices')
        .doc(token)
        .set({
          'uid': uid,
          'fcmToken': token,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> _saveResponderToken({
    required String uid,
    required String role,
    required String token,
  }) {
    return FirebaseFirestore.instance
        .collection('staff_tokens')
        .doc(uid)
        .collection('devices')
        .doc(token)
        .set({
          'uid': uid,
          'role': role,
          'fcmToken': token,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }
}
