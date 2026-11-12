import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/incident_service.dart';
import '../theme/app_theme.dart';

class MyReportsScreen extends StatelessWidget {
  const MyReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipOval(
              child: Image.asset(
                'assets/images/safecampus_logo.png',
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            const Text('My Reports'),
          ],
        ),
        backgroundColor: SafeCampusColors.forest,
        foregroundColor: Colors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [SafeCampusColors.forest, SafeCampusColors.green],
            ),
          ),
        ),
      ),
      body: user == null
          ? const Center(child: Text('Sign in to view your reports.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: IncidentService().watchMyIncidents(user.uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load reports: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final reports = [...snapshot.data!.docs]
                  ..sort((a, b) {
                    final aDate = a.data()['createdAt'];
                    final bDate = b.data()['createdAt'];
                    if (aDate is! Timestamp || bDate is! Timestamp) return 0;
                    return bDate.compareTo(aDate);
                  });
                if (reports.isEmpty) {
                  return const Center(
                    child: Text('You have not submitted any reports yet.'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final data = reports[index].data();
                    final status = data['status']?.toString() ?? 'pending';
                    final teams = data['recipientTeams'];
                    return Card(
                      color: SafeCampusColors.paper,
                      elevation: 2,
                      shadowColor: SafeCampusColors.forest.withValues(
                        alpha: 0.12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                        side: const BorderSide(
                          color: SafeCampusColors.gold,
                          width: 1,
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          data['reportType'] == 'sos'
                              ? Icons.warning_amber_rounded
                              : Icons.report_problem_outlined,
                          color: SafeCampusColors.green,
                        ),
                        title: Text(
                          data['category']?.toString() ?? 'Report',
                          style: const TextStyle(
                            color: SafeCampusColors.forest,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Status: ${_statusLabel(status)}\n'
                            'Location: ${data['location'] ?? 'Not provided'}\n'
                            'Routed to: ${_teamLabels(teams)}',
                          ),
                        ),
                        isThreeLine: true,
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: SafeCampusColors.gold,
                        ),
                        onTap: () => _showDetails(context, data),
                      ),
                    );
                  },
                );
              },
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

  String _teamLabels(dynamic teams) {
    if (teams is! List) return 'Campus Security';
    return teams
        .map((team) {
          switch (team) {
            case 'campus_security':
              return 'Campus Security';
            case 'medical_services':
              return 'Medical Services';
            case 'fire_services':
              return 'Fire Services';
            case 'student_welfare':
              return 'Student Welfare';
            default:
              return team.toString();
          }
        })
        .join(', ');
  }

  void _showDetails(BuildContext context, Map<String, dynamic> data) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(data['category']?.toString() ?? 'Report details'),
        content: SingleChildScrollView(
          child: Text(
            'Status: ${_statusLabel(data['status']?.toString() ?? 'pending')}\n\n'
            'Description: ${data['description'] ?? '—'}\n\n'
            'Location: ${data['location'] ?? '—'}'
            '${data['latitude'] is num && data['longitude'] is num ? '\nGPS: ${data['latitude']}, ${data['longitude']}' : ''}\n\n'
            'Routed to: ${_teamLabels(data['recipientTeams'])}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }
}
