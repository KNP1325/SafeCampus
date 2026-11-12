import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/admin_service.dart';
import '../services/auth_service.dart';
import '../services/responder_notification_service.dart';
import '../services/safety_locations_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'responder_queue_screen.dart';
import 'safety_location_dialog.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _service = AdminService();
  final _safetyLocations = SafetyLocationsService();
  String _period = 'month';

  bool _inPeriod(Object? created) {
    if (_period == 'all') return true;
    if (created is! Timestamp) return false;
    final now = DateTime.now();
    final start = _period == 'week'
        ? DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: now.weekday - 1))
        : DateTime(now.year, now.month);
    return !created.toDate().isBefore(start);
  }

  late final Future<bool> _adminAccess = _verifyAdmin();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ResponderNotificationService.instance.registerCurrentDevice();
      } catch (error) {
        _showMessage('Admin notifications could not be enabled: $error');
      }
    });
  }

  Future<bool> _verifyAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final claims = (await user.getIdTokenResult(true)).claims ?? {};
    return claims['admin'] == true || claims['role'] == 'admin';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _approveStaff(String uid) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    if (adminUid == null) return;
    try {
      await _service.approveStaff(uid, adminUid);
    } catch (error) {
      _showMessage('Could not approve staff: $error');
      return;
    }
    _showMessage('Staff approved as campus security.');
  }

  Future<void> _setAccountStatus(String uid, String nextStatus) async {
    final isSuspending = nextStatus == 'suspended';
    final isInactive = nextStatus == 'inactive';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isSuspending
              ? 'Suspend account?'
              : isInactive
              ? 'Mark account inactive?'
              : 'Reactivate account?',
        ),
        content: Text(
          isSuspending
              ? 'This marks the account as suspended (for abuse or false alarms). Only an administrator can reactivate it. Firebase Authentication is not disabled, so do not treat this as a security-grade suspension.'
              : isInactive
              ? 'Use this for graduates or students who have left. The student can reactivate herself later by signing in with her verified university email.'
              : 'This restores app access for the account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              isSuspending
                  ? 'SUSPEND'
                  : isInactive
                  ? 'MARK INACTIVE'
                  : 'REACTIVATE',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.setAccountStatus(uid: uid, status: nextStatus);
    } catch (error) {
      _showMessage('Could not update account status: $error');
      return;
    }
    _showMessage(
      isSuspending
          ? 'Account suspended.'
          : isInactive
          ? 'Account marked inactive.'
          : 'Account reactivated.',
    );
  }

  String _roleLabel(String role) => switch (role) {
    'campus_security' => 'Security Officer',
    'medical_services' => 'Medical Services',
    'fire_services' => 'Fire Services',
    'student_welfare' => 'Student Welfare',
    'admin' => 'Administrator',
    _ => 'Student',
  };

  Future<void> _exportIncidents(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) async {
    if (documents.isEmpty) {
      _showMessage('There are no incident records to export yet.');
      return;
    }
    final rows = <List<String>>[
      ['Incident ID', 'Created', 'Category', 'Status', 'Student', 'Location'],
      for (final document in documents)
        [
          document.id,
          _timestampText(document.data()['createdAt']),
          '${document.data()['category'] ?? ''}',
          '${document.data()['status'] ?? ''}',
          '${document.data()['studentName'] ?? ''}',
          '${document.data()['location'] ?? ''}',
        ],
    ];
    final csv = rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(csv)),
              mimeType: 'text/csv',
              name: 'safecampus_incident_report.csv',
            ),
          ],
          text: 'SafeCampus incident report',
        ),
      );
    } catch (error) {
      _showMessage('Could not export the incident report: $error');
    }
  }

  String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

  String _timestampText(Object? value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _adminAccess,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Admin Dashboard')),
            body: Center(
              child: Text('Could not verify admin access: ${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data != true) {
          return Scaffold(
            appBar: AppBar(title: const Text('Admin Dashboard')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Administrator access is required to open this dashboard.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  ClipOval(
                    child: Image.asset(
                      'assets/images/safecampus_logo.png',
                      width: 42,
                      height: 42,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Admin Dashboard', style: TextStyle(fontSize: 16)),
                      Text(
                        'SafeCampus • feel safe on campus',
                        style: TextStyle(
                          color: SafeCampusColors.gold,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              backgroundColor: SafeCampusColors.forest,
              foregroundColor: Colors.white,
              bottom: const TabBar(
                isScrollable: true,
                labelColor: SafeCampusColors.gold,
                unselectedLabelColor: Colors.white70,
                indicatorColor: SafeCampusColors.gold,
                tabs: [
                  Tab(text: 'Overview', icon: Icon(Icons.insights_outlined)),
                  Tab(
                    text: 'Accounts',
                    icon: Icon(Icons.manage_accounts_outlined),
                  ),
                  Tab(text: 'Campus Data', icon: Icon(Icons.place_outlined)),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'About account management',
                  icon: const Icon(
                    Icons.info_outline,
                    color: SafeCampusColors.gold,
                  ),
                  onPressed: _showAccountsInfo,
                ),
                IconButton(
                  tooltip: 'Log out',
                  icon: const Icon(Icons.logout, color: SafeCampusColors.gold),
                  onPressed: _confirmLogout,
                ),
              ],
            ),
            body: TabBarView(
              children: [
                _buildOverview(),
                _buildAccounts(),
                _buildCampusData(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverview() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchIncidents(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _errorPanel(
            'Could not load incident analytics: ${snapshot.error}',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final incidents = snapshot.data!.docs
            .where((d) => _inPeriod(d.data()['createdAt']))
            .toList();
        final statusCounts = <String, int>{};
        final responseMinutes = <double>[];
        final resolutionMinutes = <double>[];
        for (final incident in incidents) {
          final data = incident.data();
          final status = '${data['status'] ?? 'unknown'}';
          statusCounts.update(status, (count) => count + 1, ifAbsent: () => 1);
          final created = data['createdAt'];
          final acknowledged = data['acknowledgedAt'];
          if (created is Timestamp && acknowledged is Timestamp) {
            responseMinutes.add(
              acknowledged.toDate().difference(created.toDate()).inSeconds / 60,
            );
          }
          final resolved = data['resolvedAt'];
          if (created is Timestamp && resolved is Timestamp) {
            resolutionMinutes.add(
              resolved.toDate().difference(created.toDate()).inSeconds / 60,
            );
          }
        }
        final averageResponse = responseMinutes.isEmpty
            ? null
            : responseMinutes.reduce((a, b) => a + b) / responseMinutes.length;
        final averageResolution = resolutionMinutes.isEmpty
            ? null
            : resolutionMinutes.reduce((a, b) => a + b) /
                  resolutionMinutes.length;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Campus safety at a glance',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in const {
                  'week': 'This week',
                  'month': 'This month',
                  'all': 'All time',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _period == entry.key,
                    onSelected: (_) => setState(() => _period = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _metricCard(
                  'Total incidents',
                  '${incidents.length}',
                  openFilter: 'all',
                ),
                _metricCard(
                  'Pending',
                  '${statusCounts['pending'] ?? 0}',
                  tint: const Color(0xFFFBE8B5),
                  openFilter: 'pending',
                ),
                _metricCard(
                  'Resolved',
                  '${statusCounts['resolved'] ?? 0}',
                  tint: const Color(0xFFCDE6CF),
                  openFilter: 'resolved',
                ),
                _metricCard(
                  'Avg. acknowledgement',
                  averageResponse == null
                      ? 'No data'
                      : _formatMinutes(averageResponse),
                ),
                _metricCard(
                  'Avg. time to resolve',
                  averageResolution == null
                      ? 'No data'
                      : _formatMinutes(averageResolution),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _exportIncidents(incidents),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export incident report (CSV)'),
            ),
          ],
        );
      },
    );
  }

  String _formatMinutes(double minutes) {
    if (minutes < 60) return '${minutes.round()} min';
    final hours = (minutes / 60).floor();
    final mins = (minutes % 60).round();
    if (hours < 24) return '${hours}h ${mins}m';
    return '${hours ~/ 24}d ${hours % 24}h';
  }

  Widget _metricCard(
    String title,
    String value, {
    Color? tint,
    String? openFilter,
  }) {
    return Card(
      color: tint ?? const Color(0xFFE5E7E1),
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: openFilter == null
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ResponderQueueScreen(initialFilter: openFilter),
                ),
              ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(color: SafeCampusColors.forest),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: SafeCampusColors.forest),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _copyRoleCommand(String uid, bool isManager) async {
    final role = isManager ? 'admin' : 'campus_security';
    await Clipboard.setData(
      ClipboardData(
        text: 'npm --prefix functions run set-staff-role -- $uid $role',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Command copied. Run it in the project folder (change the role if needed).',
        ),
      ),
    );
  }

  void _showAccountsInfo() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('About account management'),
        content: const Text(
          'Students activate after verifying their @mywsu.ac.za email.\n\n'
          'Staff and administrator roles are assigned by a trusted operator using the set-staff-role command (use "Copy role command" on a pending request).\n\n'
          'On the free plan, "Suspend" only blocks app access; it does not disable Firebase Authentication. "Mark inactive" is for graduates: the student can reactivate herself by signing in with her verified email. Permanent deletion needs a trusted backend.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  Widget _buildAccounts() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchUsers(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _errorPanel('Could not load accounts: ${snapshot.error}');
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final users = [...snapshot.data!.docs]
          ..sort((a, b) {
            final aCreated = a.data()['createdAt'];
            final bCreated = b.data()['createdAt'];
            if (aCreated is Timestamp && bCreated is Timestamp) {
              return bCreated.compareTo(aCreated);
            }
            if (aCreated is Timestamp) return -1;
            if (bCreated is Timestamp) return 1;
            return a.id.compareTo(b.id);
          });
        if (users.isEmpty) {
          return const Center(child: Text('No accounts found.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final document = users[index];
            final data = document.data();
            final status = '${data['accountStatus'] ?? 'pending'}';
            final isStaffRequest = data['accountType'] == 'staff_request';
            final isManagerRequest = data['accountType'] == 'manager_request';
            final role = data['role'] as String?;
            final verified = data['isVerified'] == true;
            final canToggle =
                !isManagerRequest &&
                role != 'admin' &&
                verified &&
                (status == 'active' ||
                    status == 'suspended' ||
                    status == 'inactive');
            final needsRole =
                isManagerRequest && (role == null || role.isEmpty);
            final roleText = needsRole
                ? 'Role not assigned'
                : isStaffRequest && (role == null || role.isEmpty)
                ? 'Awaiting email verification'
                : _roleLabel(role ?? 'student');
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${data['fullName'] ?? data['email'] ?? document.id}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('${data['email'] ?? 'No email'}'),
                    Text(
                      isManagerRequest
                          ? 'Administrator request · Staff number: ${data['staffNumber'] ?? 'Not provided'}'
                          : isStaffRequest
                          ? 'Staff request · Staff number: ${data['staffNumber'] ?? 'Not provided'}'
                          : 'Campus number: ${data['studentNumber'] ?? 'Not provided'}',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _chip(
                          roleText,
                          role == 'admin'
                              ? Colors.green.shade800
                              : needsRole
                              ? Colors.amber.shade800
                              : Colors.blueGrey,
                        ),
                        _chip(
                          status[0].toUpperCase() + status.substring(1),
                          status == 'active'
                              ? Colors.green.shade700
                              : status == 'suspended'
                              ? Colors.red.shade700
                              : status == 'inactive'
                              ? Colors.blueGrey
                              : Colors.amber.shade800,
                        ),
                        _chip(
                          verified ? 'Verified' : 'Verification pending',
                          verified
                              ? Colors.green.shade700
                              : Colors.amber.shade800,
                        ),
                      ],
                    ),
                    if (canToggle) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (status == 'active') ...[
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _setAccountStatus(document.id, 'inactive'),
                              icon: const Icon(Icons.school_outlined),
                              label: const Text('Mark inactive'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _setAccountStatus(document.id, 'suspended'),
                              icon: const Icon(Icons.block),
                              label: const Text('Suspend'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                              ),
                            ),
                          ] else if (status == 'inactive')
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _setAccountStatus(document.id, 'suspended'),
                              icon: const Icon(Icons.block),
                              label: const Text('Suspend'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                              ),
                            ),
                          if (status != 'active')
                            FilledButton.icon(
                              onPressed: () =>
                                  _setAccountStatus(document.id, 'active'),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Reactivate account'),
                            ),
                        ],
                      ),
                    ],
                    if (isStaffRequest && status == 'pending') ...[
                      const SizedBox(height: 8),
                      verified
                          ? FilledButton.icon(
                              onPressed: () => _approveStaff(document.id),
                              icon: const Icon(Icons.verified_user),
                              label: const Text('Approve as campus security'),
                            )
                          : const Text(
                              'Waiting for the staff member to verify their email.',
                            ),
                    ],
                    if (needsRole) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _copyRoleCommand(document.id, isManagerRequest),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy role command'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCampusData() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildHelplinesEditor(),
        const SizedBox(height: 12),
        _buildSafetyLocationsEditor(),
      ],
    );
  }

  Widget _buildSafetyLocationsEditor() {
    return StreamBuilder<List<SafetyLocation>>(
      stream: _safetyLocations.watch(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _errorPanel(
            'Could not load safety locations: ${snapshot.error}',
          );
        }
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final locations = snapshot.data!;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Campus safety locations',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Shown in student Helpline Contacts. No map coordinates are needed.',
                ),
                if (locations.isEmpty)
                  const Text('No safety locations configured.'),
                for (final location in locations)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(location.name),
                    subtitle: Text(location.description),
                    onTap: () => _editSafetyLocation(location),
                    trailing: IconButton(
                      tooltip: 'Remove safety location',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removeSafetyLocation(location),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _editSafetyLocation(null),
                  icon: const Icon(Icons.add),
                  label: const Text('Add safety location'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editSafetyLocation(SafetyLocation? location) async {
    final result = await showDialog<({String name, String description})>(
      context: context,
      builder: (_) => SafetyLocationDialog(location: location),
    );
    if (result == null) return;
    try {
      await _safetyLocations.save(
        id: location?.id,
        name: result.name,
        description: result.description,
      );
      if (mounted) _showMessage('Safety location saved.');
    } catch (error) {
      if (mounted) _showMessage('Could not save safety location: $error');
    }
  }

  Future<void> _removeSafetyLocation(SafetyLocation location) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove safety location?'),
        content: Text('Remove ${location.name} from Helpline Contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _safetyLocations.delete(location.id);
      if (mounted) _showMessage('Safety location removed.');
    } catch (error) {
      if (mounted) _showMessage('Could not remove safety location: $error');
    }
  }

  Widget _buildHelplinesEditor() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _service.watchHelplines(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _errorPanel(
            'Could not load helpline contacts: ${snapshot.error}',
          );
        }
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final rawContacts = snapshot.data!.data()?['contacts'];
        final contacts = rawContacts is List
            ? rawContacts.whereType<Map>().map((value) {
                return {
                  'name': '${value['name'] ?? ''}',
                  'phone': '${value['phone'] ?? ''}',
                };
              }).toList()
            : <Map<String, String>>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Emergency helplines',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (contacts.isEmpty) const Text('No helplines configured.'),
                for (var index = 0; index < contacts.length; index++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(contacts[index]['name']!),
                    subtitle: Text(contacts[index]['phone']!),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editHelpline(contacts, index),
                    ),
                    leading: IconButton(
                      tooltip: 'Remove helpline',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removeHelpline(contacts, index),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _editHelpline(contacts, null),
                  icon: const Icon(Icons.add),
                  label: const Text('Add helpline'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editHelpline(
    List<Map<String, String>> contacts,
    int? editIndex,
  ) async {
    final nameController = TextEditingController(
      text: editIndex == null ? '' : contacts[editIndex]['name'],
    );
    final phoneController = TextEditingController(
      text: editIndex == null ? '' : contacts[editIndex]['phone'],
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(editIndex == null ? 'Add helpline' : 'Edit helpline'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Service name'),
            ),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    if (save == true) {
      final name = nameController.text.trim();
      final phone = phoneController.text.trim();
      if (name.isEmpty || phone.isEmpty) {
        _showMessage('Enter both a service name and phone number.');
      } else {
        final updated = [...contacts];
        final contact = {'name': name, 'phone': phone};
        if (editIndex == null) {
          updated.add(contact);
        } else {
          updated[editIndex] = contact;
        }
        try {
          await _service.saveHelplines(updated);
          _showMessage('Helpline contacts saved.');
        } catch (error) {
          _showMessage('Could not save helplines: $error');
        }
      }
    }
    Future.delayed(const Duration(milliseconds: 500), () {
      nameController.dispose();
      phoneController.dispose();
    });
  }

  Future<void> _removeHelpline(
    List<Map<String, String>> contacts,
    int index,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove helpline?'),
        content: Text(
          'Remove ${contacts[index]['name']} from campus contacts?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final updated = [...contacts]..removeAt(index);
    try {
      await _service.saveHelplines(updated);
      _showMessage('Helpline removed.');
    } catch (error) {
      _showMessage('Could not remove helpline: $error');
    }
  }

  Widget _errorPanel(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }

  Future<void> _confirmLogout() async {
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
      _showMessage('Could not unregister notifications before logout: $error');
    }
    try {
      await AuthService().signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (error) {
      _showMessage('Could not sign out: ${error.message ?? error.code}');
    }
  }
}
