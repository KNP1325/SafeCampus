import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(email)) {
      _showDialog(
        'Invalid Email',
        'Please enter a valid email address.',
        Icons.error_outline,
        Colors.red,
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      await AuthService().sendPasswordResetEmail(email);
      if (!mounted) return;
      _showDialog(
        'Check Your Email',
        'If an account exists for $email, Firebase has sent it a password reset link. Follow the link to choose a new password.',
        Icons.mark_email_unread_outlined,
        SafeCampusColors.forest,
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        _showDialog(
          'Could Not Send Reset Email',
          _resetErrorMessage(error),
          Icons.error_outline,
          Colors.red,
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _resetErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'too-many-requests':
        return 'Too many reset requests. Please wait and try again later.';
      case 'network-request-failed':
        return 'Could not connect to Firebase. Check your internet connection.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled in Firebase Authentication.';
      default:
        return 'Firebase could not send the reset email (${error.code}). Please try again.';
    }
  }

  void _showDialog(String title, String content, IconData icon, Color color) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
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
            const Text('Reset Password'),
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
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [SafeCampusColors.paper, Color(0xFFF0F1E6)],
            ),
          ),
          child: Theme(
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Container(
                    width: 104,
                    height: 104,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.78),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: SafeCampusColors.gold,
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_reset,
                      size: 58,
                      color: SafeCampusColors.forest,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Reset Your Password',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: SafeCampusColors.forest,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter your account email and Firebase will send you a secure password reset link.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isSending ? null : _sendResetEmail,
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
                    child: _isSending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('SEND RESET LINK'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
