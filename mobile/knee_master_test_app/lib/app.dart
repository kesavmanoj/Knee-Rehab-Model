import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/auth/auth_repository.dart';
import 'src/models/app_role.dart';
import 'src/models/user_profile.dart';
import 'src/repositories/doctor_repository.dart';
import 'src/repositories/profile_repository.dart';
import 'src/repositories/session_repository.dart';
import 'src/ui/doctor_home_screen.dart';
import 'src/ui/knee_home_screen.dart';
import 'src/ui/login_screen.dart';

class KneeMasterTestApp extends StatelessWidget {
  const KneeMasterTestApp({
    super.key,
    required this.authRepository,
    required this.sessionRepository,
    required this.doctorRepository,
    required this.profileRepository,
  });

  final AuthRepository authRepository;
  final SessionRepository sessionRepository;
  final DoctorRepository doctorRepository;
  final ProfileRepository profileRepository;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0B8F8C),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Knee Rehab Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: colorScheme.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
      ),
      home: _AppShell(
        authRepository: authRepository,
        sessionRepository: sessionRepository,
        doctorRepository: doctorRepository,
        profileRepository: profileRepository,
      ),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell({
    required this.authRepository,
    required this.sessionRepository,
    required this.doctorRepository,
    required this.profileRepository,
  });

  final AuthRepository authRepository;
  final SessionRepository sessionRepository;
  final DoctorRepository doctorRepository;
  final ProfileRepository profileRepository;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  StreamSubscription<AuthState>? _authSubscription;
  UserProfile? _profile;
  bool _initializing = true;
  bool _signingIn = false;
  String? _authError;
  String? _authInfo;

  @override
  void initState() {
    super.initState();
    _authSubscription = widget.authRepository.authStateChanges.listen((_) {
      _loadProfile();
    });
    _loadProfile();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _initializing = true;
      _authError = null;
    });

    try {
      final profile = await widget.authRepository.fetchCurrentProfile();
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = profile;
        _initializing = false;
      });
      if (profile?.role == AppRole.patient) {
        unawaited(widget.sessionRepository.retryPendingUploads());
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = null;
        _authError = 'Failed to restore account: $error';
        _initializing = false;
      });
    }
  }

  Future<void> _handleLogin(String email, String password) async {
    setState(() {
      _signingIn = true;
      _authError = null;
      _authInfo = null;
    });
    try {
      await widget.authRepository.signIn(email: email, password: password);
      await _loadProfile();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _authError = 'Sign-in failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _signingIn = false;
        });
      }
    }
  }

  Future<void> _handleSignUp({
    required String email,
    required String password,
    required String displayName,
    required AppRole role,
  }) async {
    setState(() {
      _signingIn = true;
      _authError = null;
      _authInfo = null;
    });
    try {
      await widget.authRepository.signUp(
        email: email,
        password: password,
        displayName: displayName,
        role: role,
      );
      await _loadProfile();
      if (mounted && _profile == null) {
        setState(() {
          _authInfo =
              'Account created. If email confirmation is enabled in Supabase, confirm your email and then sign in.';
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _authError = 'Sign-up failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _signingIn = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await widget.authRepository.signOut();
    if (!mounted) {
      return;
    }
    setState(() {
      _profile = null;
      _authError = null;
      _authInfo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final profile = _profile;
    if (profile == null) {
      return LoginScreen(
        onLogin: _handleLogin,
        onSignUp: _handleSignUp,
        errorMessage: _authError,
        infoMessage: _authInfo,
        isBusy: _signingIn,
      );
    }

    switch (profile.role) {
      case AppRole.patient:
        return KneeHomeScreen(
          profile: profile,
          sessionRepository: widget.sessionRepository,
          profileRepository: widget.profileRepository,
          onLogout: _logout,
        );
      case AppRole.doctor:
        return DoctorHomeScreen(
          profile: profile,
          doctorRepository: widget.doctorRepository,
          sessionRepository: widget.sessionRepository,
          onLogout: _logout,
        );
    }
  }
}
