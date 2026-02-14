
import 'package:flutter/material.dart';
import 'package:speed_data/features/screens/admin/tabs/setup_tab.dart'; // To be created
import 'package:speed_data/features/screens/admin/tabs/registration_tab.dart'; // To be created
import 'package:speed_data/features/screens/admin/tabs/timing_tab.dart'; // To be created

class AdminDashboardTabs extends StatefulWidget {
  const AdminDashboardTabs({Key? key}) : super(key: key);

  @override
  State<AdminDashboardTabs> createState() => _AdminDashboardTabsState();
}

class _AdminDashboardTabsState extends State<AdminDashboardTabs> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RACE CONTROL CONSOLE'),
        backgroundColor: Colors.black,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.settings), text: 'SETUP'),
            Tab(icon: Icon(Icons.app_registration), text: 'REGISTRATION'),
            Tab(icon: Icon(Icons.timer), text: 'TIMING'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: const [
           SetupTab(),
           RegistrationTab(),
           TimingTab(),
        ],
      ),
    );
  }
}
