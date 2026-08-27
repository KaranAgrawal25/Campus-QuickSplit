import 'package:flutter/material.dart';

import '../dashboard/dashboard_screen.dart';
import '../groups/groups_screen.dart';
import '../activity/activity_screen.dart';
import '../more/more_screen.dart';

/// Bottom-nav shell. Groups/Activity/More are intentionally simple
/// placeholder screens for Phase 1 — they get real content in Phase 2
/// (Groups), Phase 3 (Activity), and Phase 5 (Analytics/Settings under
/// More). Keeping the shell itself final now means later phases only
/// swap out the child screens, not the navigation scaffolding.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _screens = [
    DashboardScreen(),
    GroupsScreen(),
    ActivityScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            label: 'Groups',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
