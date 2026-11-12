import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/safety_locations_service.dart';
import '../theme/app_theme.dart';

class HelplineContactsScreen extends StatelessWidget {
  const HelplineContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
            const Text('Helpline Contacts'),
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
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'Emergency helplines',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: SafeCampusColors.forest,
              fontWeight: FontWeight.bold,
            ),
          ),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('campus_settings')
                .doc('helplines')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  'Could not load emergency contacts: ${snapshot.error}',
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rawContacts = snapshot.data!.data()?['contacts'];
              final contacts = rawContacts is List
                  ? rawContacts.whereType<Map>().toList()
                  : <Map>[];
              if (contacts.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Campus helpline contacts have not been added yet. If there is immediate danger, use your local emergency number.',
                  ),
                );
              }
              return Column(
                children: [
                  for (final contact in contacts)
                    Card(
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
                        leading: const Icon(
                          Icons.phone_in_talk_outlined,
                          color: SafeCampusColors.green,
                        ),
                        title: Text(
                          '${contact['name'] ?? 'Emergency service'}',
                          style: const TextStyle(
                            color: SafeCampusColors.forest,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text('${contact['phone'] ?? ''}'),
                        trailing: IconButton(
                          tooltip: 'Call',
                          icon: const Icon(
                            Icons.call_outlined,
                            color: SafeCampusColors.green,
                          ),
                          onPressed: () async {
                            final phone = '${contact['phone'] ?? ''}'.trim();
                            final uri = Uri(scheme: 'tel', path: phone);
                            if (phone.isEmpty || !await launchUrl(uri)) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Could not open the phone dialer.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Campus safety locations',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: SafeCampusColors.forest,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'Locations only; phone numbers are listed under emergency helplines.',
          ),
          StreamBuilder<List<SafetyLocation>>(
            stream: SafetyLocationsService().watch(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  'Could not load safety locations: ${snapshot.error}',
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'No campus safety locations have been added yet.',
                  ),
                );
              }
              return Column(
                children: [
                  for (final location in snapshot.data!)
                    Card(
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
                        leading: const Icon(
                          Icons.location_on_outlined,
                          color: SafeCampusColors.green,
                        ),
                        title: Text(location.name),
                        subtitle: Text(location.description),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
