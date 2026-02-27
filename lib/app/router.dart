import 'package:go_router/go_router.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/ward_select_screen.dart';
import '../features/dashboard/dashboard_screen.dart';

GoRouter createRouter() {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/ward-select',
        builder: (context, state) => const WardSelectScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
    ],
  );
}
