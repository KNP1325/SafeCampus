import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/incident_service.dart';
import '../services/responder_notification_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'my_reports_screen.dart';
import 'profile_screen.dart';
import 'report_incident_screen.dart';
import 'responder_queue_screen.dart';
import 'helpline_contacts_screen.dart';
import 'campus_safe_map_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerResponderDevice();
    });
  }

  Future<void> _registerResponderDevice() async {
    try {
      await ResponderNotificationService.instance.registerCurrentDevice();
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'SafeCampus push notifications could not be enabled (${error.code}).',
          ),
        ),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'SafeCampus push notifications could not be enabled: ${error.message}',
          ),
        ),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Press Logout to return to the Login screen.'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/images/safecampus_logo.png',
                  width: 44,
                  height: 30,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(FirebaseAuth.instance.currentUser?.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final profile = snapshot.data?.data();
                    final fullName = profile?['fullName'] as String?;
                    final firstName = profile?['firstName'] as String?;
                    final surname = profile?['surname'] as String?;
                    final name = fullName?.trim().isNotEmpty == true
                        ? fullName!.trim()
                        : [firstName, surname]
                              .whereType<String>()
                              .map((part) => part.trim())
                              .where((part) => part.isNotEmpty)
                              .join(' ');
                    final greetingName = name.isNotEmpty
                        ? name
                        : FirebaseAuth.instance.currentUser?.displayName ??
                              'SafeCampus';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Hello, $greetingName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const Text(
                          'SafeCampus Dashboard',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          backgroundColor: SafeCampusColors.forest,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'My profile',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileScreen(),
                  ),
                );
              },
            ),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser?.uid)
                  .snapshots(),
              builder: (context, profileSnapshot) {
                final profile = profileSnapshot.data?.data();
                final isSecurity =
                    profile?['role'] == 'campus_security' &&
                    profile?['accountStatus'] == 'active';
                return FutureBuilder<IdTokenResult?>(
                  future: FirebaseAuth.instance.currentUser?.getIdTokenResult(),
                  builder: (context, snapshot) {
                    final claims = snapshot.data?.claims ?? {};
                    final role = claims['role'];
                    final canRespond =
                        isSecurity ||
                        claims['admin'] == true ||
                        (role is String &&
                            const {
                              'admin',
                              'campus_security',
                              'medical_services',
                              'fire_services',
                              'student_welfare',
                            }.contains(role));
                    if (!canRespond) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.health_and_safety_outlined),
                      tooltip: 'Responder queue',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ResponderQueueScreen(),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: () => _showLogoutDialog(context),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // SOS Quick Alert Card
              Card(
                color: Colors.red[700],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 48,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'EMERGENCY SOS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap below to capture your location for an SOS alert.',
                        style: TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _triggerSos(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red[800],
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: const Text(
                          'TRIGGER SOS NOW',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: SafeCampusColors.forest,
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _buildMenuCard(
                    context,
                    icon: Icons.report_problem_outlined,
                    title: 'Report Incident',
                    color: Colors.orange[800]!,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ReportIncidentScreen(),
                        ),
                      );
                    },
                  ),
                  _buildMenuCard(
                    context,
                    icon: Icons.history,
                    title: 'My Reports',
                    color: Colors.blue[800]!,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MyReportsScreen(),
                        ),
                      );
                    },
                  ),
                  _buildMenuCard(
                    context,
                    icon: Icons.phone_in_talk_outlined,
                    title: 'Helpline Contacts',
                    color: Colors.green[800]!,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const HelplineContactsScreen(),
                        ),
                      );
                    },
                  ),
                  _buildMenuCard(
                    context,
                    icon: Icons.map_outlined,
                    title: 'Campus Safe Map',
                    color: Colors.purple[800]!,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CampusSafeMapScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _triggerSos(BuildContext context) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Turn on Location services to capture your GPS position.',
            ),
            action: SnackBarAction(
              label: 'SETTINGS',
              onPressed: () async {
                await Geolocator.openLocationSettings();
              },
            ),
          ),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (!context.mounted) return;

      if (permission == LocationPermission.deniedForever) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Location permission needed'),
            content: const Text(
              'Allow location access in your phone settings to capture your position for an SOS.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await Geolocator.openAppSettings();
                },
                child: const Text('OPEN SETTINGS'),
              ),
            ],
          ),
        );
        return;
      }

      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission was not granted. No SOS location was captured.',
            ),
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

      if (!context.mounted) return;
      try {
        await IncidentService().createSosAlert(position);
      } on FirebaseException catch (error) {
        if (!context.mounted) return;
        final reason = error.code == 'permission-denied'
            ? 'Firestore rejected the alert. Confirm that firestore.rules has been deployed.'
            : error.message ?? 'Firebase error ${error.code}.';
        await _showSosResult(
          context,
          title: 'SOS Was Not Saved',
          message:
              'Location was captured at ${position.latitude}, ${position.longitude}, but no emergency alert reached Firestore. $reason',
          position: position,
        );
        return;
      } on StateError catch (error) {
        if (!context.mounted) return;
        await _showSosResult(
          context,
          title: 'SOS Was Not Saved',
          message:
              'Location was captured at ${position.latitude}, ${position.longitude}, but no alert was saved. ${error.message}',
          position: position,
        );
        return;
      }

      if (!context.mounted) return;
      await _showSosResult(
        context,
        title: 'SOS Alert Saved',
        message:
            'Latitude: ${position.latitude}\nLongitude: ${position.longitude}\n\nYour SOS is pending in the Campus Security responder queue. Automatic phone/email notifications are not configured yet. If you are in immediate danger, contact campus security through its official emergency channel.',
        position: position,
      );
    } on LocationServiceDisabledException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are turned off.')),
      );
    } on PermissionDeniedException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission was denied.')),
      );
    } on TimeoutException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not get your location in time. Please try again.',
          ),
        ),
      );
    }
  }

  Future<void> _showSosResult(
    BuildContext context, {
    required String title,
    required String message,
    Position? position,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          if (position != null)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _openInGoogleMaps(context, position);
              },
              icon: const Icon(Icons.map_outlined),
              label: const Text('OPEN IN GOOGLE MAPS'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _openInGoogleMaps(
    BuildContext context,
    Position position,
  ) async {
    final mapsUrl = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${position.latitude},${position.longitude}',
    });

    try {
      final opened = await launchUrl(
        mapsUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')),
        );
      }
    } on PlatformException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open Google Maps: ${error.message}'),
          ),
        );
      }
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text(
            'Are you sure you want to log out of SafeCampus?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  try {
                    await ResponderNotificationService.instance
                        .unregisterCurrentDevice();
                  } on FirebaseException catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Could not remove this device from responder notifications (${error.code}). Signing out anyway.',
                          ),
                        ),
                      );
                    }
                  } on PlatformException catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Could not disable responder notifications: ${error.message}. Signing out anyway.',
                          ),
                        ),
                      );
                    }
                  }
                  await AuthService().signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                    (route) => false,
                  );
                } on FirebaseAuthException catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Could not sign out: ${error.message ?? error.code}',
                      ),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('LOGOUT'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: SafeCampusColors.forest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
