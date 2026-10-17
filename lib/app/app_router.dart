import 'package:akshi/features/domains/domain/domain_finding.dart';
import 'package:akshi/features/domains/presentation/attention_screen.dart';
import 'package:akshi/features/domains/presentation/home_screen.dart';
import 'package:akshi/features/domains/presentation/domain_detail_screen.dart';
import 'package:akshi/features/domains/presentation/domain_dns_screen.dart';
import 'package:akshi/features/domains/presentation/domain_overview_screen.dart';
import 'package:akshi/features/domains/presentation/domain_form_screen.dart';
import 'package:akshi/features/reminders/domain/expiry_alarm.dart';
import 'package:akshi/features/reminders/presentation/reminder_ledger_screen.dart';
import 'package:akshi/features/settings/presentation/crash_logs_screen.dart';
import 'package:akshi/features/settings/presentation/about_screen.dart';
import 'package:akshi/features/settings/presentation/network_destinations_screen.dart';
import 'package:akshi/features/settings/presentation/settings_screen.dart';
import 'package:akshi/features/tags/presentation/tags_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Defines the app's top-level screens and focused domain child routes.
///
/// A domain opens at its overview; attention and notification destinations can
/// then route directly to domain, TLS, email, or DNS detail context.
final appRouter = GoRouter(
  routes: <RouteBase>[
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/attention',
      builder: (context, state) => AttentionScreen(
        source: state.uri.queryParameters['source'] ?? 'current',
        alarmDate: state.uri.queryParameters['date'],
        domainIds:
            state.uri.queryParameters['ids']
                ?.split(',')
                .where((id) => id.isNotEmpty)
                .toList(growable: false) ??
            const <String>[],
      ),
    ),
    GoRoute(
      path: '/domain/new',
      pageBuilder: (context, state) =>
          _sheetPage(state: state, child: const DomainFormScreen.create()),
    ),
    GoRoute(
      path: '/domain/:id',
      builder: (context, state) =>
          DomainOverviewScreen(domainId: state.pathParameters['id']!),
      routes: <RouteBase>[
        GoRoute(
          path: 'registration',
          builder: (context, state) => DomainDetailScreen(
            domainId: state.pathParameters['id']!,
            focusKind: DomainCheckKind.domainRegistration,
            revealAttention: state.uri.queryParameters['attention'] == '1',
          ),
        ),
        GoRoute(
          path: 'tls',
          builder: (context, state) => DomainDetailScreen(
            domainId: state.pathParameters['id']!,
            focusKind: DomainCheckKind.tlsCertificate,
            revealAttention: state.uri.queryParameters['attention'] == '1',
          ),
        ),
        GoRoute(
          path: 'email',
          builder: (context, state) => DomainDetailScreen(
            domainId: state.pathParameters['id']!,
            focusKind: DomainCheckKind.emailConfiguration,
            revealAttention: state.uri.queryParameters['attention'] == '1',
          ),
        ),
        GoRoute(
          path: 'dns',
          builder: (context, state) =>
              DomainDnsScreen(domainId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'edit',
          pageBuilder: (context, state) => _sheetPage(
            state: state,
            child: DomainFormScreen.edit(domainId: state.pathParameters['id']!),
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
          path: 'crash-logs',
          builder: (context, state) => const CrashLogsScreen(),
        ),
        GoRoute(
          path: 'reminder-ledger',
          builder: (context, state) => const ReminderLedgerScreen(),
          routes: <RouteBase>[
            GoRoute(
              path: ':date',
              builder: (context, state) => ReminderLedgerDetailScreen(
                date: AlarmDate.parse(state.pathParameters['date']!),
              ),
            ),
          ],
        ),
        GoRoute(
          path: 'network-destinations',
          builder: (context, state) => const NetworkDestinationsScreen(),
        ),
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
