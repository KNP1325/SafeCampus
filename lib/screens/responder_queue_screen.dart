import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/incident_service.dart';
import '../services/responder_notification_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class ResponderQueueScreen extends StatefulWidget {
  const ResponderQueueScreen({super.key, this.initialFilter = 'all'});

  /// One of: pending, resolved, all.
  final String initialFilter;

  @override
  State<ResponderQueueScreen> createState() => _ResponderQueueScreenState();
}

class _ResponderQueueScreenState extends State<ResponderQueueScreen> {
  final _incidentService = IncidentService();
  late String _filter = widget.initialFilter;
  late final Future<String?> _teamFuture = _getResponderTeam();
  final Set<String> _updating = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ResponderNotificationService.instance.registerCurrentDevice();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Responder notifications could not be enabled: $error',
            ),
          ),
        );
      }
    });
  }

  Future<String?> _getResponderTeam() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final claims = (await user.getIdTokenResult()).claims ?? {};
    final role = claims['role'];
    if (role is String &&
        const {
          'admin',
          'campus_security',
          'medical_services',
          'fire_services',
          'student_welfare',
        }.contains(role)) {
      return role;
    }
    if (claims['admin'] == true) return 'admin';
    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = profile.data();
    if (data?['role'] == 'campus_security' &&
        data?['accountStatus'] == 'active') {
      return 'campus_security';
    }
    return null;
  }

  Future<void> _advance(
    String team,
    QueryDocumentSnapshot<Map<String, dynamic>> document,
    String nextStatus,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _updating.add(document.id));
    try {
      await _incidentService.advanceStatus(
        incidentId: document.id,
        currentStatus: document.data()['status']?.toString() ?? 'pending',
        nextStatus: nextStatus,
        responderId: user.uid,
      );
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not update incident (${error.code}). ${error.message ?? 'Check responder permissions.'}',
            ),
          ),
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _updating.remove(document.id));
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will be returned to the SafeCampus login screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('LOG OUT'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ResponderNotificationService.instance.unregisterCurrentDevice();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not unregister notifications before logout: $error',
          ),
        ),
      );
    }
    try {
      await AuthService().signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not sign out: ${error.message ?? error.code}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipOval(
              child: Image.asset(
                'assets/images/safecampus_logo.png',
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Responder Queue'),
          ],
        ),
        backgroundColor: SafeCampusColors.forest,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout, color: SafeCampusColors.gold),
            onPressed: _signOut,
          ),
        ],
      ),
      body: FutureBuilder<String?>(
        future: _teamFuture,
        builder: (context, teamSnapshot) {
          if (teamSnapshot.hasError) {
            return Center(
              child: Text(
                'Could not verify responder access: ${teamSnapshot.error}',
              ),
            );
          }
          if (!teamSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final team = teamSnapshot.data;
          if (team == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This screen is for authorized campus responders. Your account does not have a responder role.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _incidentService.watchTeamIncidents(team),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load the responder queue: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final incidents =
                  snapshot.data!.docs.where((document) {
                    final s =
                        document.data()['status']?.toString() ?? 'pending';
                    return switch (_filter) {
                      'pending' => s == 'pending',
                      'resolved' => s == 'resolved',
                      _ => true,
                    };
                  }).toList()..sort((a, b) {
                    final aDate = a.data()['createdAt'];
                    final bDate = b.data()['createdAt'];
                    if (aDate is! Timestamp || bDate is! Timestamp) return 0;
                    return aDate.compareTo(bDate);
                  });
              final filterBar = SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final entry in const {
                      'pending': 'Pending',
                      'resolved': 'Resolved',
                      'all': 'All',
                    }.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          showCheckmark: false,
                          avatar: _filter == entry.key
                              ? const Icon(
                                  Icons.check,
                                  size: 18,
                                  color: SafeCampusColors.forest,
                                )
                              : null,
                          label: Text(entry.value),
                          selected: _filter == entry.key,
                          selectedColor: SafeCampusColors.paleGreen,
                          backgroundColor: SafeCampusColors.paper,
                          labelStyle: const TextStyle(
                            color: SafeCampusColors.forest,
                            fontWeight: FontWeight.w600,
                          ),
                          side: const BorderSide(
                            color: SafeCampusColors.forest,
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                          onSelected: (_) =>
                              setState(() => _filter = entry.key),
                        ),
                      ),
                  ],
                ),
              );
              return Column(
                children: [
                  filterBar,
                  Expanded(
                    child: incidents.isEmpty
                        ? const Center(
                            child: Text('No incidents match this filter.'),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: incidents.length,
                            itemBuilder: (context, index) {
                              final document = incidents[index];
                              final data = document.data();
                              return _buildIncidentCard(team, document, data);
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildIncidentCard(
    String team,
    QueryDocumentSnapshot<Map<String, dynamic>> document,
    Map<String, dynamic> data,
  ) {
    final status = data['status']?.toString() ?? 'pending';
    final updating = _updating.contains(document.id);
    final isSecurity = team == 'campus_security' || team == 'admin';
    final isAdminView = team == 'admin';
    String? nextStatus;
    String? actionLabel;
    if (isAdminView) {
      // Admins oversee incidents; security handles the response.
    } else if (status == 'pending') {
      nextStatus = 'acknowledged';
      actionLabel = 'ACKNOWLEDGE';
    } else if (status == 'acknowledged' && isSecurity) {
      nextStatus = 'dispatched';
      actionLabel = 'DISPATCH';
    } else if (status == 'acknowledged' || status == 'dispatched') {
      nextStatus = 'resolved';
      actionLabel = 'MARK RESOLVED';
    }

    final teams = data['recipientTeams'];
    final isSos = (data['category']?.toString() ?? '').toLowerCase().contains(
      'sos',
    );
    final hasGps = data['latitude'] is num && data['longitude'] is num;
    return Card(
      color: SafeCampusColors.paper,
      elevation: 3,
      shadowColor: SafeCampusColors.forest.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: SafeCampusColors.gold, width: 1.4),
      ),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (isSos)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                      size: 26,
                    ),
                  ),
                Expanded(
                  child: Text(
                    data['category']?.toString() ?? 'Incident',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSos
                          ? Colors.red.shade700
                          : SafeCampusColors.forest,
                    ),
                  ),
                ),
                _statusChip(status),
              ],
            ),
            const SizedBox(height: 6),
            Text('Location: ${data['location'] ?? 'Not provided'}'),
            if (hasGps) ...[
              Text('GPS: ${data['latitude']}, ${data['longitude']}'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _openMap(
                    (data['latitude'] as num).toDouble(),
                    (data['longitude'] as num).toDouble(),
                  ),
                  icon: const Icon(
                    Icons.map_outlined,
                    color: SafeCampusColors.forest,
                  ),
                  label: const Text('View on Map'),
                  style: TextButton.styleFrom(
                    foregroundColor: SafeCampusColors.forest,
                  ),
                ),
              ),
            ],
            const Divider(height: 24),
            Text('Student: ${data['studentName'] ?? 'Not provided'}'),
            Text('Student number: ${data['studentNumber'] ?? 'Not provided'}'),
            Text('Phone: ${data['studentPhone'] ?? 'Not provided'}'),
            if (_hasPhone(data['studentPhone']))
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _call(data['studentPhone'].toString()),
                  icon: const Icon(Icons.phone, color: SafeCampusColors.forest),
                  label: const Text('Call Student'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SafeCampusColors.forest,
                    side: const BorderSide(color: SafeCampusColors.gold),
                  ),
                ),
              ),
            Text(
              'Campus/residence: ${data['campus'] ?? '—'} / '
              '${data['residenceBlock'] ?? '—'} ${data['room'] ?? ''}',
            ),
            const SizedBox(height: 8),
            Text('Details: ${data['description'] ?? ''}'),
            Text(
              'Teams: ${teams is List ? teams.join(', ') : 'campus_security'}',
            ),
            if (data['emergencyContacts'] is List &&
                (data['emergencyContacts'] as List).isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Emergency contacts',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final contact in data['emergencyContacts'] as List)
                if (contact is Map)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${contact['name'] ?? ''} '
                          '(${contact['relationship'] ?? ''}): ${contact['phone'] ?? ''}',
                        ),
                      ),
                      if (_hasPhone(contact['phone']))
                        IconButton(
                          tooltip: 'Call ${contact['name'] ?? 'contact'}',
                          icon: const Icon(
                            Icons.phone,
                            color: SafeCampusColors.green,
                          ),
                          onPressed: () => _call(contact['phone'].toString()),
                        ),
                    ],
                  ),
            ],
            if (isAdminView) ...[
              const SizedBox(height: 8),
              const Text(
                'View only: security responds to incidents.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
            if (actionLabel != null && nextStatus != null) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: updating
                    ? null
                    : () => _advance(team, document, nextStatus!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SafeCampusColors.forest,
                  foregroundColor: Colors.white,
                  side: const BorderSide(
                    color: SafeCampusColors.gold,
                    width: 1.2,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: updating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasPhone(Object? phone) =>
      phone != null &&
      phone.toString().replaceAll(RegExp(r'\D'), '').length >= 7;

  Future<void> _launch(Uri uri, String failure) async {
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  Future<void> _call(String phone) => _launch(
    Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), '')),
    'Could not open the phone dialer.',
  );

  Future<void> _openMap(double lat, double lng) => _launch(
    Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
    'Could not open maps.',
  );

  Widget _statusChip(String status) {
    final color = switch (status) {
      'pending' => Colors.red.shade700,
      'acknowledged' => Colors.orange.shade800,
      'dispatched' => Colors.blue.shade700,
      _ => Colors.green.shade700,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _statusLabel(status).toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'acknowledged':
        return 'Acknowledged';
      case 'dispatched':
        return 'Responders dispatched';
      case 'resolved':
        return 'Resolved';
      default:
        return status;
    }
  }
}
