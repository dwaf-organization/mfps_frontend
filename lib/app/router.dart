import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/auth/ward_select_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/notification/notification_page.dart';

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
      GoRoute(
        path: '/notification',
        builder: (context, state) => const NotificationPage(),
      ),
    ],
  );
}
