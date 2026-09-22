import 'package:akshi/features/monitors/domain/monitor_finding.dart';
import 'package:akshi/features/monitors/presentation/attention_screen.dart';
import 'package:akshi/features/monitors/presentation/home_screen.dart';
import 'package:akshi/features/monitors/presentation/monitor_detail_screen.dart';
import 'package:akshi/features/monitors/presentation/monitor_form_screen.dart';
import 'package:akshi/features/settings/presentation/about_screen.dart';
import 'package:akshi/features/settings/presentation/settings_screen.dart';
import 'package:akshi/features/tags/presentation/tags_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

final appRouter = GoRouter(
  routes: <RouteBase>[
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/attention',
      builder: (context, state) => AttentionScreen(
        source: state.uri.queryParameters['source'] ?? 'current',
        monitorIds:
            state.uri.queryParameters['ids']
                ?.split(',')
                .where((id) => id.isNotEmpty)
                .toList(growable: false) ??
            const <String>[],
      ),
    ),
    GoRoute(
      path: '/monitor/new',
      pageBuilder: (context, state) =>
          _sheetPage(state: state, child: const MonitorFormScreen()),
    ),
    GoRoute(
      path: '/monitor/:id',
      builder: (context, state) => MonitorDetailScreen(
        monitorId: state.pathParameters['id']!,
        focusKind: MonitorCheckKind.fromId(
          state.uri.queryParameters['focus'],
        ),
      ),
      routes: <RouteBase>[
        GoRoute(
          path: 'edit',
          pageBuilder: (context, state) => _sheetPage(
            state: state,
            child: MonitorFormScreen(monitorId: state.pathParameters['id']!),
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
      routes: <RouteBase>[
        GoRoute(path: 'tags', builder: (context, state) => const TagsScreen()),
        GoRoute(
          path: 'about',
          builder: (context, state) => const AboutScreen(),
        ),
      ],
    ),
  ],
);

CustomTransitionPage<void> _sheetPage({
  required GoRouterState state,
  required Widget child,
}) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 380),
  reverseTransitionDuration: const Duration(milliseconds: 280),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .06),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  },
);
