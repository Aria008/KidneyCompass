import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../pages/login_page.dart';
import '../pages/landing_page.dart';
import '../pages/register_page.dart';
import '../pages/home_page.dart';
import '../pages/not_found_page.dart';
import '../pages/journal_page.dart';
import '../pages/track_page.dart';
import '../pages/insights_page.dart';
import '../pages/profile_page.dart';
import '../pages/analyzer_page.dart';
import '../widgets/nav.dart';
import 'dart:async';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/home', // Start at home, let redirect handle auth
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isLoggedIn = session != null;

      // Auth pages (accessible when NOT logged in)
      final authPages = ['/login', '/register', '/'];
      final isAuthPage = authPages.contains(state.uri.path);

      print('=== ROUTER REDIRECT ===');
      print('Current path: ${state.uri.path}');
      print('Is logged in: $isLoggedIn');
      print('Is auth page: $isAuthPage');

      if (!isLoggedIn && !isAuthPage) {
        print('Redirecting to login - no session');
        return '/login';
      }

      if (isLoggedIn && isAuthPage) {
        print('Redirecting to home - has session');
        return '/home';
      }

      print('No redirect needed');
      print('=======================');
      return null; // No redirect needed
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LandingPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          final location = state.uri.toString();
          final index = switch (location) {
            '/home' => 0,
            '/journal' => 1,
            '/analyzer' => 2,
            '/insights' => 3,
            '/profile' => 4,
            _ => 0,
          };
          return Scaffold(
            body: child,
            bottomNavigationBar: BottomNavBar(currentIndex: index),
          );
        },
        routes: [
          GoRoute(path: '/home', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/journal',
            builder: (context, state) => const JournalPage(),
          ),
          GoRoute(
            path: '/analyzer',
            builder: (context, state) => CKDHealthAnalyzer(),
          ),
          GoRoute(
            path: '/insights',
            builder: (context, state) => const InsightsPage(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => const NotFoundPage(),
    refreshListenable: GoRouterRefreshStream(
      Supabase.instance.client.auth.onAuthStateChange,
    ),
  );
}

// Helper class to make GoRouter refresh when auth state changes
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<AuthState> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((AuthState data) {
      print('Auth state changed in router - Session: ${data.session != null}');
      notifyListeners();
    });
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
