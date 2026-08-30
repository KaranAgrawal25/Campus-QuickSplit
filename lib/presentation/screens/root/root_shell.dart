import 'package:flutter/material.dart';

import '../dashboard/dashboard_screen.dart';
import '../groups/groups_screen.dart';
import '../activity/activity_screen.dart';
import '../more/more_screen.dart';

/// Bottom-navigation shell. Each tab owns a real application screen; the
/// IndexedStack keeps tab state and scroll position intact while switching.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  // These widgets belong to this shell instance. Keeping them in a static
  // const list can reuse the same widget configurations if the startup gate
  // rebuilds its shell while a pushed route is active, which violates the
  // ownership assumptions of inherited/provider dependents on deactivation.
  // A state-owned list still preserves each tab through IndexedStack.
  late final List<Widget> _screens = [
    DashboardScreen(key: UniqueKey()),
    GroupsScreen(key: UniqueKey()),
    ActivityScreen(key: UniqueKey()),
    MoreScreen(key: UniqueKey()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded),
            label: 'Groups',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
