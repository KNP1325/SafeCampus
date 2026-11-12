import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../services/incident_service.dart';
import '../theme/app_theme.dart';

class ReportIncidentScreen extends StatefulWidget {
  const ReportIncidentScreen({super.key});

  @override
  State<ReportIncidentScreen> createState() => _ReportIncidentScreenState();
}

class _ReportIncidentScreenState extends State<ReportIncidentScreen> {
  String _selectedCategory = 'Theft / Burglary';
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  final List<String> _categories = [
    'Theft / Burglary',
    'Suspicious Activity',
    'Vandalism',
    'Medical Assistance',
    'Fire Emergency',
    'Harassment',
    'Other',
  ];

  Future<void> _submitReport() async {
    final location = _locationController.text.trim();
    final description = _descriptionController.text.trim();
    if (location.isEmpty || description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter both the incident location and details.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await IncidentService().submitIncident(
        category: _selectedCategory,
        location: location,
        description: description,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedCategory == 'Medical Assistance'
                ? 'Report queued for Campus Security and Medical Services.'
                : _selectedCategory == 'Fire Emergency'
                ? 'Report queued for Campus Security and Fire Services.'
                : _selectedCategory == 'Harassment'
                ? 'Report queued for Campus Security and Student Welfare.'
                : 'Report queued for Campus Security.',
          ),
        ),
      );
      Navigator.pop(context);
    } on FirebaseException catch (error) {
      if (!mounted) return;
      final reason = error.code == 'permission-denied'
          ? 'Firestore rejected the report. Confirm that firestore.rules has been deployed.'
          : error.message ?? 'Firebase error ${error.code}.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Report was not saved. $reason')));
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Report an Incident'),
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
      body: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.72),
            prefixIconColor: SafeCampusColors.green,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 17,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: SafeCampusColors.forest),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: SafeCampusColors.forest),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(
                color: SafeCampusColors.green,
                width: 1.8,
              ),
            ),
          ),
        ),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [SafeCampusColors.paper, Color(0xFFF0F1E6)],
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Incident Category',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: _categories.map((String category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    if (newValue != null) {
                      setState(() => _selectedCategory = newValue);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: 'Location (e.g., Library 2nd Floor, Residence B)',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Incident Details / Description',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submitReport,
                  icon: const Icon(Icons.send),
                  label: _isSubmitting
                      ? const Text('SAVING REPORT...')
                      : const Text('SUBMIT REPORT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SafeCampusColors.forest,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                    side: const BorderSide(
                      color: SafeCampusColors.gold,
                      width: 1.5,
                    ),
                    shape: const StadiumBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
