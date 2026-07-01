import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'router/app_router.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    // Wait for Supabase to restore the session from storage
    await Future.delayed(const Duration(milliseconds: 300));

    final session = Supabase.instance.client.auth.currentSession;

    print('=== AUTH GATE INIT ===');
    print('Session exists: ${session != null}');
    if (session != null) {
      print('User ID: ${session.user.id}');
      print('User email: ${session.user.email}');
      print('Expires at: ${session.expiresAt}');
      print('Is expired: ${session.isExpired}');
    }
    print('======================');

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading...'),
              ],
            ),
          ),
        ),
      );
    }

    // Once loading is done, show the main app with router
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'CKD Tracker',
      routerConfig: AppRouter.router,
      theme: ThemeData(primarySwatch: Colors.blue),
    );
  }
}
