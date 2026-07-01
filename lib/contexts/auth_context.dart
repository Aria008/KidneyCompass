import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool isAuthenticated = false;
  User? user;
  bool isLoading = true;

  // Cached row from the `profiles` table
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? get profile => _profile;

  AuthProvider() {
    _loadUser();
  }

  Future<void> _loadUser() async {
    user = _supabase.auth.currentUser;
    isAuthenticated = user != null;
    if (isAuthenticated) {
      await _loadProfile();
    } else {
      _profile = null;
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> _loadProfile() async {
    if (user == null) {
      _profile = null;
      return;
    }

    final row =
        await _supabase
            .from('profiles')
            .select('*')
            .eq('id', user!.id)
            .maybeSingle();

    _profile = row;
  }

  Future<bool> login(String email, String password) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.user != null) {
      user = response.user;
      isAuthenticated = true;
      await _loadProfile();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> register(String email, String password) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
    );

    if (response.user != null) {
      user = response.user;
      isAuthenticated = true;
      await _loadProfile();
      notifyListeners();
      return true;
    }
    return false;
  }

  void logout() async {
    await _supabase.auth.signOut();
    user = null;
    _profile = null;
    isAuthenticated = false;
    notifyListeners();
  }
}
