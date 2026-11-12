import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _campusController = TextEditingController();
  final _residenceBlockController = TextEditingController();
  final _roomController = TextEditingController();
  final List<_EmergencyContactFields> _contacts = [];
  final User? _user = FirebaseAuth.instance.currentUser;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  String _studentNumber = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _surnameController.dispose();
    _phoneController.dispose();
    _campusController.dispose();
    _residenceBlockController.dispose();
    _roomController.dispose();
    for (final contact in _contacts) {
      contact.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = _user;
    if (user == null) {
      setState(() {
        _loadError = 'You need to sign in to view your profile.';
        _isLoading = false;
      });
      return;
    }

    final email = user.email ?? '';
    final emailStudentNumber = email.split('@').first;
    if (!RegExp(r'^\d{9}$').hasMatch(emailStudentNumber)) {
      setState(() {
        _studentNumber = emailStudentNumber;
        _loadError = 'Your email must begin with your 9-digit student number (for example, 123456789@mywsu.ac.za). Contact support if this is not your student email.';
        _isLoading = false;
      });
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snapshot.data() ?? <String, dynamic>{};
      _studentNumber = emailStudentNumber;
      _firstNameController.text =
          (data['firstName'] as String?) ??
          user.displayName?.split(' ').first ??
          '';
      _surnameController.text = (data['surname'] as String?) ?? '';
      _phoneController.text = (data['phoneNumber'] as String?) ?? '';
      _campusController.text = (data['campus'] as String?) ?? '';
      _residenceBlockController.text =
          (data['residenceBlock'] as String?) ?? '';
      _roomController.text = (data['room'] as String?) ?? '';

      final savedContacts = data['emergencyContacts'];
      if (savedContacts is List && savedContacts.isNotEmpty) {
        for (final savedContact in savedContacts) {
          if (savedContact is Map) {
            _contacts.add(
              _EmergencyContactFields(
                name: savedContact['name']?.toString() ?? '',
                relationship: savedContact['relationship']?.toString() ?? '',
                phone: savedContact['phone']?.toString() ?? '',
              ),
            );
          }
        }
      }
      if (_contacts.isEmpty) _contacts.add(_EmergencyContactFields());

      if (mounted) setState(() => _isLoading = false);
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError =
            'Could not load your profile (${error.code}). ${error.message ?? 'Check your connection and Firestore rules.'}';
        _isLoading = false;
      });
    }
  }

  void _addContact() {
    if (_contacts.length >= 3) return;
    setState(() => _contacts.add(_EmergencyContactFields()));
  }

  void _removeContact(int index) {
    if (_contacts.length <= 1) return;
    final removed = _contacts.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final user = _user;
    if (user == null) {
      _showMessage('You need to sign in before saving your profile.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'firstName': _firstNameController.text.trim(),
        'surname': _surnameController.text.trim(),
        'fullName':
            '${_firstNameController.text.trim()} ${_surnameController.text.trim()}',
        'studentNumber': _studentNumber,
        'phoneNumber': _phoneController.text.trim(),
        'campus': _campusController.text.trim(),
        'residenceBlock': _residenceBlockController.text.trim(),
        'room': _roomController.text.trim(),
        'emergencyContacts': _contacts
            .map(
              (contact) => {
                'name': contact.name.text.trim(),
                'relationship': contact.relationship.text.trim(),
                'phone': contact.phone.text.trim(),
              },
            )
            .toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved successfully.')),
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;
      final message = error.code == 'permission-denied'
          ? 'Firestore denied the save. Deploy the latest firestore.rules and try again.'
          : 'Could not save your profile (${error.code}). ${error.message ?? 'Please try again.'}';
      _showMessage(message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required.';
    return null;
  }

  String? _validatePhone(String? value, String label) {
    final requiredError = _required(value, label);
    if (requiredError != null) return requiredError;
    final digits = value!.replaceAll(RegExp(r'[\s()+-]'), '');
    if (!RegExp(r'^\d{7,15}$').hasMatch(digits)) {
      return 'Enter a valid phone number (7–15 digits).';
    }
    return null;
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(labelText: label, prefixIcon: Icon(icon));
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: SafeCampusColors.green),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: SafeCampusColors.forest,
            ),
          ),
        ],
      ),
    );
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
            const Text('My Profile'),
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
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: SafeCampusColors.green),
            )
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          : Form(
              key: _formKey,
              child: Theme(
                data: Theme.of(context).copyWith(
                  inputDecorationTheme: InputDecorationTheme(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.72),
                    prefixIconColor: SafeCampusColors.green,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(
                        color: SafeCampusColors.forest,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(
                        color: SafeCampusColors.forest,
                      ),
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
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _sectionTitle('Student Profile', Icons.school_outlined),
                      TextFormField(
                        controller: _firstNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _decoration(
                          'Full name',
                          Icons.person_outline,
                        ),
                        validator: (value) => _required(value, 'Full name'),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _surnameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _decoration(
                          'Surname',
                          Icons.badge_outlined,
                        ),
                        validator: (value) => _required(value, 'Surname'),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        initialValue: _user?.email ?? '',
                        readOnly: true,
                        decoration: _decoration(
                          'Student email',
                          Icons.email_outlined,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        initialValue: _studentNumber,
                        readOnly: true,
                        decoration: _decoration(
                          'Student number / ID number (9 digits)',
                          Icons.credit_card_outlined,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9+()\s-]'),
                          ),
                        ],
                        decoration: _decoration(
                          'Phone number',
                          Icons.phone_outlined,
                        ),
                        validator: (value) =>
                            _validatePhone(value, 'Phone number'),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _campusController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _decoration('Campus', Icons.location_city),
                        validator: (value) => _required(value, 'Campus'),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _residenceBlockController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _decoration(
                          'Residence block',
                          Icons.apartment_outlined,
                        ),
                        validator: (value) =>
                            _required(value, 'Residence block'),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _roomController,
                        decoration: _decoration(
                          'Room number',
                          Icons.door_front_door,
                        ),
                        validator: (value) => _required(value, 'Room number'),
                      ),
                      _sectionTitle(
                        'Emergency Contacts (ICE)',
                        Icons.contact_emergency_outlined,
                      ),
                      const Text(
                        'Add 1–3 people we can contact in an emergency.',
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      for (var index = 0; index < _contacts.length; index++)
                        _buildContactCard(index),
                      if (_contacts.length < 3)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _addContact,
                            icon: const Icon(Icons.add),
                            label: const Text('ADD EMERGENCY CONTACT'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: SafeCampusColors.forest,
                              side: const BorderSide(
                                color: SafeCampusColors.gold,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SafeCampusColors.forest,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(54),
                          elevation: 3,
                          side: const BorderSide(
                            color: SafeCampusColors.gold,
                            width: 1.5,
                          ),
                          shape: const StadiumBorder(),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('SAVE PROFILE'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildContactCard(int index) {
    final contact = _contacts[index];
    return Card(
      color: SafeCampusColors.paper,
      elevation: 2,
      shadowColor: SafeCampusColors.forest.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: SafeCampusColors.gold, width: 1),
      ),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Contact ${index + 1}',
                    style: const TextStyle(
                      color: SafeCampusColors.forest,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_contacts.length > 1)
                  IconButton(
                    tooltip: 'Remove contact',
                    onPressed: () => _removeContact(index),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: SafeCampusColors.forest,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: contact.name,
              textCapitalization: TextCapitalization.words,
              decoration: _decoration('Contact name', Icons.person_outline),
              validator: (value) =>
                  _required(value, 'Contact ${index + 1} name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: contact.relationship,
              textCapitalization: TextCapitalization.words,
              decoration: _decoration(
                'Relationship (e.g. parent, guardian)',
                Icons.people_outline,
              ),
              validator: (value) =>
                  _required(value, 'Contact ${index + 1} relationship'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: contact.phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+()\s-]')),
              ],
              decoration: _decoration(
                'Contact phone number',
                Icons.phone_outlined,
              ),
              validator: (value) =>
                  _validatePhone(value, 'Contact ${index + 1} phone number'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyContactFields {
  _EmergencyContactFields({
    String name = '',
    String relationship = '',
    String phone = '',
  }) : name = TextEditingController(text: name),
       relationship = TextEditingController(text: relationship),
       phone = TextEditingController(text: phone);

  final TextEditingController name;
  final TextEditingController relationship;
  final TextEditingController phone;

  void dispose() {
    name.dispose();
    relationship.dispose();
    phone.dispose();
  }
}
