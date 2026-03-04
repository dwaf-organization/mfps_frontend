import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/auth/ward_select_page.dart';
import '../features/dashboard/dashboard_page.dart';

GoRouter buildAppRouter() {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/ward-select',
        builder: (context, state) => const WardSelectPage(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardPage(),
      ),
    ],
  );
}
