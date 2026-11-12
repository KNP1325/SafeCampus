import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    this.isStaffRegistration = false,
    this.isManagerRegistration = false,
  });

  final bool isStaffRegistration;
  final bool isManagerRegistration;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _fullNameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isRegistering = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _surnameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegistration() async {
    final fullName = _fullNameController.text.trim();
    final surname = _surnameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (fullName.isEmpty ||
        surname.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      _showMessageDialog(
        'Missing Information',
        'Please fill in all fields, including your full name and surname.',
      );
      return;
    }

    final normalizedEmail = email.toLowerCase();
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      _showMessageDialog(
        'Invalid Email',
        'Please enter a valid email address.',
      );
      return;
    }

    if (!widget.isStaffRegistration &&
        !widget.isManagerRegistration &&
        (!RegExp(r'^\d{9}@mywsu\.ac\.za$').hasMatch(normalizedEmail))) {
      _showMessageDialog(
        'Invalid Student Email',
        'Use your 9-digit student number followed by @mywsu.ac.za (for example, 123456789@mywsu.ac.za).',
      );
      return;
    }

    final uppercaseRegex = RegExp(r'[A-Z]');
    final specialCharRegex = RegExp(r'[!@#$%^&*(),.?":{}|<>]');

    if (password.length < 8 ||
        !uppercaseRegex.hasMatch(password) ||
        !specialCharRegex.hasMatch(password)) {
      _showMessageDialog(
        'Weak Password',
        'Password must be at least 8 characters long, contain at least 1 capital letter, and 1 special character.',
      );
      return;
    }

    if (password != confirmPassword) {
      _showMessageDialog(
        'Password Mismatch',
        'Passwords do not match. Please check and try again.',
      );
      return;
    }

    setState(() => _isRegistering = true);
    try {
      final result = await AuthService().createAccount(
        firstName: fullName,
        surname: surname,
        email: email,
        password: password,
        accountType: widget.isManagerRegistration
            ? 'manager_request'
            : widget.isStaffRegistration
            ? 'staff_request'
            : 'student',
      );
      if (mounted) _showSuccessAndRedirectDialog(result.staffNumber);
    } on FirebaseAuthException catch (error) {
      if (AuthService().currentUser != null) {
        await AuthService().signOut();
      }
      if (mounted) {
        if (error.code == 'email-already-in-use') {
          _showAccountExistsDialog();
        } else if (error.code == 'too-many-requests' ||
            error.code == 'network-request-failed') {
          _showMessageDialog(
            'Verification Email Could Not Be Sent',
            'Your account may have been created, but Firebase could not send the verification email. Try signing in to request another verification email.',
          );
        } else {
          _showMessageDialog(
            'Registration Failed',
            _registrationErrorMessage(error),
          );
        }
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        final reason = error.code == 'permission-denied'
            ? 'Firestore rejected the profile write. Deploy the provided Firestore rules and try registering again.'
            : error.message ?? 'Firebase error ${error.code}.';
        _showMessageDialog(
          'Profile Could Not Be Saved',
          'Your Firebase Authentication account may already have been created, but its profile was not saved. $reason If you can, try logging in.',
        );
      }
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  String _registrationErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Firebase rejected this password as too weak. Please use a stronger password.';
      case 'operation-not-allowed':
        return 'Email and password sign-up is not enabled in Firebase Authentication. Enable the Email/Password provider in your Firebase project.';
      case 'network-request-failed':
        return 'Could not connect to Firebase. Check your internet connection.';
      default:
        return 'Firebase sign-up failed (${error.code}). Please try again.';
    }
  }

  void _showAccountExistsDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(
              child: Text('Account Exists', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: const Text(
          'An account with this email address already exists. Please log in instead.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _navigateToLogin();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B2A4A),
              foregroundColor: Colors.white,
            ),
            child: const Text('GO TO LOGIN'),
          ),
        ],
      ),
    );
  }

  void _showSuccessAndRedirectDialog(String? staffNumber) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Registration Successful',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (staffNumber != null) ...[
                const Text('Your unique 9-digit Staff Number is:'),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 20,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      staffNumber,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: Color(0xFF1B2A4A),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Please save this number. It is your SafeCampus staff ID.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                widget.isManagerRegistration
                    ? 'Your administrator access request has been created. Verify your email, then wait for the system owner to assign your admin role. Sign in with your email and password.'
                    : widget.isStaffRegistration
                    ? 'Your campus security account has been created. Verify your email, then wait for an administrator to approve your account. Sign in with your email and password.'
                    : 'We sent a verification link to your university email. Verify your email, then sign in. Your student account will activate automatically after verification.',
              ),
            ],
          ),
        ),
        actions: [
          if (staffNumber != null)
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: staffNumber));
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Staff number copied.')),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('COPY'),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _navigateToLogin();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B2A4A),
              foregroundColor: Colors.white,
            ),
            child: const Text('GO TO LOGIN'),
          ),
        ],
      ),
    );
  }

  void _navigateToLogin() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  void _showMessageDialog(String title, String content) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
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
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isManagerRegistration
                ? 'Request Admin Access'
                : widget.isStaffRegistration
                ? 'Register Staff Account'
                : 'Register Student Account',
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
              fillColor: Colors.white.withValues(alpha: 0.52),
              prefixIconColor: SafeCampusColors.green,
              suffixIconColor: SafeCampusColors.green,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 18,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: SafeCampusColors.forest),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: SafeCampusColors.forest),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: SafeCampusColors.green,
                  width: 1.8,
                ),
              ),
            ),
          ),
          child: Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [SafeCampusColors.paper, Color(0xFFF0F1E6)],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 24,
                right: -24,
                child: IgnorePointer(
                  child: Transform.rotate(
                    angle: -0.5,
                    child: Icon(
                      Icons.eco_outlined,
                      size: 190,
                      color: SafeCampusColors.green.withValues(alpha: 0.07),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                left: -38,
                child: IgnorePointer(
                  child: Transform.rotate(
                    angle: 0.5,
                    child: Icon(
                      Icons.eco_outlined,
                      size: 210,
                      color: SafeCampusColors.green.withValues(alpha: 0.07),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 24,
                right: -45,
                child: IgnorePointer(
                  child: Transform.rotate(
                    angle: -0.8,
                    child: Icon(
                      Icons.eco_outlined,
                      size: 170,
                      color: SafeCampusColors.green.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: SizedBox(
                        width: 90,
                        height: 74,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(
                              Icons.person_outline,
                              size: 68,
                              color: SafeCampusColors.forest,
                            ),
                            const Positioned(
                              top: 0,
                              right: 0,
                              child: Icon(
                                Icons.add_circle,
                                size: 30,
                                color: SafeCampusColors.gold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      widget.isManagerRegistration
                          ? 'Request System Manager Access'
                          : 'Create ${widget.isStaffRegistration ? 'Staff' : 'Student'} Account',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: SafeCampusColors.forest,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _fullNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _surnameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Surname',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email address',
                        hintText:
                            widget.isManagerRegistration ||
                                widget.isStaffRegistration
                            ? 'Enter your real email for login and recovery'
                            : 'Enter your campus email address',
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'Min 8 chars, 1 capital, 1 special char',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        prefixIcon: const Icon(Icons.lock_reset),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    ElevatedButton(
                      onPressed: _isRegistering ? null : _handleRegistration,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SafeCampusColors.forest,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        elevation: 3,
                        side: const BorderSide(
                          color: SafeCampusColors.gold,
                          width: 1.5,
                        ),
                        shape: const StadiumBorder(),
                      ),
                      child: _isRegistering
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              widget.isManagerRegistration
                                  ? 'REQUEST ADMIN ACCESS'
                                  : 'REGISTER',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Flexible(
                          child: Text(
                            'Already have an account?',
                            textAlign: TextAlign.end,
                          ),
                        ),
                        TextButton(
                          onPressed: _navigateToLogin,
                          child: const Text(
                            'Login',
                            style: TextStyle(
                              color: SafeCampusColors.forest,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
