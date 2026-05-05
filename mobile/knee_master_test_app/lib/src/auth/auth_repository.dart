import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_role.dart';
import '../models/user_profile.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
    required AppRole role,
  }) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      data: <String, dynamic>{
        'display_name': displayName,
        'role': role.dbValue,
      },
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<UserProfile?> fetchCurrentProfile() async {
    final user = currentUser;
    if (user == null) {
      return null;
    }

    final profile = await _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (profile == null) {
      return null;
    }

    return UserProfile.fromMap(profile);
  }
}
