import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth_service.dart';
import 'home_screen.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'responder_queue_screen.dart';
import 'admin_dashboard_screen.dart';
import '../theme/app_theme.dart';

enum _LoginType { student, staff, admin }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoggingIn = false;
  _LoginType _loginType = _LoginType.student;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _validateAndLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    List<String> errors = [];

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');
    if (email.isEmpty) {
      errors.add('• Please enter your email address.');
    } else if (!emailRegex.hasMatch(email)) {
      errors.add('• Please enter a valid email address.');
    }

    if (password.isEmpty) {
      errors.add('• Please enter your password.');
    }

    if (errors.isNotEmpty) {
      _showErrorDialog(errors);
      return;
    }

    setState(() => _isLoggingIn = true);
    try {
      final credential = await AuthService().signIn(
        email: email,
        password: password,
      );
      final signedInUser = credential.user;
      if (signedInUser == null) {
        _showErrorDialog(['• Firebase did not return a signed-in account.']);
        return;
      }
      await signedInUser.reload();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showErrorDialog(['• Your session expired. Please sign in again.']);
        return;
      }
      final tokenResult = await user.getIdTokenResult(true);
      final claims = tokenResult.claims ?? {};
      final role = claims['role'];
      final isAdmin = claims['admin'] == true || role == 'admin';
      final isStaffClaim =
          role is String &&
          const {
            'campus_security',
            'medical_services',
            'fire_services',
            'student_welfare',
          }.contains(role);
      var isStaff = isStaffClaim;

      final profile = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      var profileData = (await profile.get()).data();

      if (profileData?['accountType'] == 'staff_request') {
        if (!user.emailVerified) {
          try {
            await user.sendEmailVerification();
          } on FirebaseAuthException {
            // Resend can be rate limited; the message below still applies.
          }
          await AuthService().signOut();
          if (mounted) {
            _showErrorDialog([
              '• Please verify your email using the link we sent, then sign in again.',
            ]);
          }
          return;
        }
        if (profileData?['isVerified'] != true) {
          try {
            await profile.update({
              'isVerified': true,
              'verifiedAt': FieldValue.serverTimestamp(),
              'verifiedBy': 'email',
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } on FirebaseException catch (error) {
            await AuthService().signOut();
            if (mounted) {
              _showErrorDialog([
                '• Your email is verified, but we could not record it (${error.code}). Please try again.',
              ]);
            }
            return;
          }
          profileData = (await profile.get()).data();
        }
        if (profileData?['accountStatus'] != 'active') {
          await AuthService().signOut();
          if (mounted) {
            _showErrorDialog([
              profileData?['accountStatus'] == 'suspended'
                  ? '• This account is suspended. Please contact the campus administrator.'
                  : '• Your email is verified. An administrator must now approve your staff account. Try again after you are approved.',
            ]);
          }
          return;
        }
        if (profileData?['accountStatus'] == 'active' &&
            profileData?['role'] == 'campus_security') {
          isStaff = true;
        }
      } else if (profileData?['accountStatus'] == 'active' &&
          profileData?['role'] == 'campus_security') {
        isStaff = true;
      }
      final isStudentAccount =
          profileData?['accountType'] == 'student' ||
          (profileData?['accountType'] == null &&
              profileData?['studentNumber'] is String);
      if (isStudentAccount) {
        final emailIsAllowed =
            user.email?.toLowerCase().endsWith('@mywsu.ac.za') ?? false;
        if (!emailIsAllowed) {
          await AuthService().signOut();
          if (mounted) {
            _showErrorDialog([
              '• Student accounts must use an official @mywsu.ac.za address.',
            ]);
          }
          return;
        }
        if (!user.emailVerified) {
          try {
            await user.sendEmailVerification();
          } on FirebaseAuthException {
            await AuthService().signOut();
            if (mounted) {
              _showErrorDialog([
                '• Your email is not verified. Check your inbox and spam folder. Firebase could not resend the verification email right now; try again later.',
              ]);
            }
            return;
          }
          await AuthService().signOut();
          if (mounted) {
            _showErrorDialog([
              '• We sent a verification link to your university email. Verify it, then sign in again to activate your account.',
            ]);
          }
          return;
        }

        if (profileData?['accountStatus'] == 'inactive' &&
            profileData?['isVerified'] == true) {
          try {
            await profile.update({
              'accountStatus': 'active',
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } on FirebaseException catch (error) {
            await AuthService().signOut();
            if (mounted) {
              _showErrorDialog([
                '• Welcome back! We could not reactivate your account (${error.code}). Please try again or contact the administrator.',
              ]);
            }
            return;
          }
          profileData = (await profile.get()).data();
        }

        if ((profileData?['accountStatus'] ?? 'pending') == 'pending' &&
            profileData?['isVerified'] != true) {
          try {
            await profile.update({
              'accountStatus': 'active',
              'isVerified': true,
              'verifiedAt': FieldValue.serverTimestamp(),
              'verifiedBy': 'email',
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } on FirebaseException catch (error) {
            await AuthService().signOut();
            if (mounted) {
              _showErrorDialog([
                '• Your email is verified, but the account could not be activated (${error.code}). Please try again or contact the administrator.',
              ]);
            }
            return;
          }
          profileData = (await profile.get()).data();
        }
      }

      final status = profileData?['accountStatus'];
      final legacyAdmin =
          isAdmin &&
          profileData != null &&
          !profileData.containsKey('accountStatus') &&
          !profileData.containsKey('isVerified');
      if (!legacyAdmin &&
          (status != 'active' || profileData?['isVerified'] != true)) {
        await AuthService().signOut();
        if (mounted) {
          _showErrorDialog([
            status == 'suspended'
                ? '• This account is suspended. Please contact the campus administrator.'
                : profileData?['accountType'] == 'manager_request'
                ? '• Your administrator access request is pending. Verify your email first. If you are setting up SafeCampus, bootstrap the first admin from your trusted project computer with the set-staff-role script; no existing admin is required.'
                : '• Your account is awaiting manual campus verification. Please contact the campus administrator.',
          ]);
        }
        return;
      }

      final hasSelectedRole = switch (_loginType) {
        _LoginType.student => !isAdmin && !isStaff,
        _LoginType.staff => isStaff,
        _LoginType.admin => isAdmin,
      };

      if (!hasSelectedRole) {
        await AuthService().signOut();
        if (mounted) {
          _showErrorDialog([
            '• This account does not have the selected ${_loginType.name} access. Choose the correct sign-in option or contact your administrator.',
          ]);
        }
        return;
      }

      final isResponder = isStaff || isAdmin;
      if (mounted) {
        _showSuccessDialog(isResponder: isResponder, isAdmin: isAdmin);
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        _showErrorDialog([_loginErrorMessage(error)]);
      }
    } on FirebaseException catch (error) {
      await AuthService().signOut();
      if (mounted) {
        _showErrorDialog([
          '• Could not verify your account status (${error.code}). Please try again.',
        ]);
      }
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  String _loginErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return '• Please enter a valid email address.';
      case 'user-disabled':
        return '• This account has been disabled. Contact support.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return '• Email or password is incorrect. Check your details or register first.';
      case 'too-many-requests':
        return '• Too many attempts. Please wait and try again.';
      case 'network-request-failed':
        return '• Could not connect to Firebase. Check your internet connection.';
      default:
        return '• Sign-in failed (${error.code}). Please try again.';
    }
  }

  void _openRegistrationOrRequestAccess() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RegisterScreen(
          isStaffRegistration: _loginType == _LoginType.staff,
          isManagerRegistration: _loginType == _LoginType.admin,
        ),
      ),
    );
  }

  void _showErrorDialog(List<String> errors) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Invalid Input'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: errors
              .map(
                (err) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(err, style: const TextStyle(fontSize: 14)),
                ),
              )
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog({required bool isResponder, required bool isAdmin}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isResponder
                  ? Icons.health_and_safety_outlined
                  : Icons.check_circle_outline,
              color: isResponder
                  ? SafeCampusColors.forest
                  : SafeCampusColors.green,
            ),
            SizedBox(width: 8),
            Text(
              isAdmin
                  ? 'Administrator Login'
                  : isResponder
                  ? 'Staff Login'
                  : 'Login Successful',
            ),
          ],
        ),
        content: Text(
          isAdmin
              ? 'Welcome. Opening the admin dashboard.'
              : isResponder
              ? 'Welcome. Opening the responder queue.'
              : 'Welcome back to SafeCampus!',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => isAdmin
                      ? const AdminDashboardScreen()
                      : isResponder
                      ? const ResponderQueueScreen()
                      : const HomeScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SafeCampusColors.forest,
              foregroundColor: Colors.white,
            ),
            child: const Text('CONTINUE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [SafeCampusColors.paper, Color(0xFFF0F1E6)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    const Text(
                      'SafeCampus',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: SafeCampusColors.forest,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Container(
                        width: 210,
                        height: 132,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: SafeCampusColors.forest.withValues(
                                alpha: 0.12,
                              ),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(
                          'assets/images/safecampus_logo.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Safe',
                            style: TextStyle(color: SafeCampusColors.gold),
                          ),
                          TextSpan(
                            text: 'Campus',
                            style: TextStyle(color: SafeCampusColors.forest),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const Text(
                      'feel safe on campus',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: SafeCampusColors.forest,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Sign in as',
                      style: TextStyle(
                        color: SafeCampusColors.forest,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<_LoginType>(
                      segments: const [
                        ButtonSegment(
                          value: _LoginType.student,
                          label: Text('Student'),
                          icon: Icon(Icons.school_outlined),
                        ),
                        ButtonSegment(
                          value: _LoginType.staff,
                          label: Text('Staff'),
                          icon: Icon(Icons.badge_outlined),
                        ),
                        ButtonSegment(
                          value: _LoginType.admin,
                          label: Text('Admin'),
                          icon: Icon(Icons.admin_panel_settings_outlined),
                        ),
                      ],
                      selected: {_loginType},
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        backgroundColor:
                            WidgetStateProperty.resolveWith<Color?>(
                              (states) => states.contains(WidgetState.selected)
                                  ? SafeCampusColors.paleGreen
                                  : Colors.transparent,
                            ),
                        foregroundColor: const WidgetStatePropertyAll(
                          SafeCampusColors.forest,
                        ),
                        side: const WidgetStatePropertyAll(
                          BorderSide(color: SafeCampusColors.forest, width: 1),
                        ),
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      onSelectionChanged: _isLoggingIn
                          ? null
                          : (selection) {
                              setState(() => _loginType = selection.first);
                            },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email address',
                        hintText: _loginType == _LoginType.admin
                            ? 'Enter your registered manager email'
                            : 'Enter the email for your account',
                        helperText: _loginType == _LoginType.admin
                            ? 'Use your email and password. Your 9-digit staff number is shown once when you register.'
                            : null,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.7),
                        prefixIcon: const Icon(Icons.email_outlined),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: SafeCampusColors.forest,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: SafeCampusColors.green,
                            width: 1.8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.7),
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
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: SafeCampusColors.forest,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: SafeCampusColors.green,
                            width: 1.8,
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const ForgotPasswordScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: SafeCampusColors.forest,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ElevatedButton(
                      onPressed: _isLoggingIn ? null : _validateAndLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SafeCampusColors.forest,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        elevation: 5,
                        side: const BorderSide(
                          color: SafeCampusColors.gold,
                          width: 1.5,
                        ),
                        shape: const StadiumBorder(),
                      ),
                      child: _isLoggingIn
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'LOGIN',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            switch (_loginType) {
                              _LoginType.student => "Don't have an account?",
                              _LoginType.staff => 'New staff member?',
                              _LoginType.admin => 'System manager?',
                            },
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              color: SafeCampusColors.forest,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _openRegistrationOrRequestAccess,
                          child: Text(
                            switch (_loginType) {
                              _LoginType.student => 'Register',
                              _LoginType.staff => 'Register Staff',
                              _LoginType.admin => 'Request Access',
                            },
                            style: const TextStyle(
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
            ),
          ),
        ),
      ),
    );
  }
}
