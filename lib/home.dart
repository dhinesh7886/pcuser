import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ✅ Import all pages correctly
import 'package:pcuser/attendance.dart';
import 'package:pcuser/bookings.dart';
import 'package:pcuser/home_widget.dart';
import 'package:pcuser/login_page.dart';
import 'package:pcuser/profile.dart';
import 'package:pcuser/leave_records.dart';
import 'package:pcuser/permission_records.dart';

class UsersHomePage extends StatefulWidget {
  final bool isShowAppBar;
  const UsersHomePage({super.key, this.isShowAppBar = true});

  @override
  State<UsersHomePage> createState() => _UsersHomePageState();
}

class _UsersHomePageState extends State<UsersHomePage> {
  int screenIndex = 0;
  User? user = FirebaseAuth.instance.currentUser;
  String? empId;
  Map<String, dynamic>? userData;

  @override
  void initState() {
    super.initState();
    _loadEmpData();
  }

  Future<void> _loadEmpData() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('id');
    if (id != null) {
      final snapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('id', isEqualTo: id)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        setState(() {
          empId = id;
          userData = snapshot.docs.first.data();
        });
      } else {
        setState(() {
          empId = id;
          userData = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isTablet = screenWidth > 600;
    final bool isLarge = screenWidth > 1000;

    List<Widget> screens = [
      const HomeWidget(),
      const CabBookingPage(),
      empId == null
          ? const Center(child: CircularProgressIndicator())
          : AttendanceScreen(userId: empId!),
    ];

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 220, 255, 250),
      appBar: widget.isShowAppBar
          ? AppBar(
              title: const Text(
                'PC Users',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: const Color.fromARGB(255, 247, 126, 227),
              centerTitle: true,
            )
          : null,

      // ✅ Responsive Drawer Section
      drawer: Drawer(
        width: isLarge ? 350 : (isTablet ? 280 : 250),
        child: empId == null
            ? const Center(child: Text("Employee ID not found"))
            : userData == null
                ? const Center(child: Text("No user profile found"))
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      DrawerHeader(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF8E2DE2),
                              Color(0xFF4A00E0),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: isTablet ? 35 : 30,
                              backgroundImage:
                                  (userData!['imageUrl'] != null &&
                                          userData!['imageUrl']
                                              .toString()
                                              .isNotEmpty)
                                      ? NetworkImage(userData!['imageUrl'])
                                      : const NetworkImage(
                                          'https://via.placeholder.com/150',
                                        ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                userData!['name'] ?? 'PC User',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isTablet ? 20 : 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _drawerItem(
                        icon: Icons.person,
                        text: 'Profile',
                        color: Colors.deepPurple,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const ProfilePage()),
                        ),
                      ),
                      _drawerItem(
                        icon: Icons.book_online_outlined,
                        text: 'Attendance',
                        onTap: () {
                          if (empId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    AttendanceScreen(userId: empId!),
                              ),
                            );
                          }
                        },
                      ),
                      _drawerItem(
                        icon: Icons.event_note, // ✅ Suitable for Leave Records
                        text: 'Leave Records',
                        onTap: () {
                          if (empId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    LeaveRecordsPage(empId: empId!),
                              ),
                            );
                          }
                        },
                      ),
                      _drawerItem(
                        icon: Icons.access_alarm, // ✅ Suitable for Permissions
                        text: 'Permission Records',
                        onTap: () {
                          if (empId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    PermissionRecordsPage(empId: empId!),
                              ),
                            );
                          }
                        },
                      ),
                      const Divider(),
                      _drawerItem(
                        icon: Icons.logout,
                        color: Colors.red,
                        text: 'Sign Out',
                        onTap: () async {
                          await FirebaseAuth.instance.signOut();
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('id');
                          if (!mounted) return;
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const StylishLoginPage()),
                          );
                        },
                      ),
                    ],
                  ),
      ),

      // ✅ Bottom Navigation
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: screenIndex,
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        onTap: (value) => setState(() => screenIndex = value),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(
              icon: Icon(Icons.local_taxi), label: "Booking"),
          BottomNavigationBarItem(
              icon: Icon(Icons.bookmark_added_rounded), label: "Attendance"),
        ],
      ),

      // ✅ Responsive Body
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: screens[screenIndex],
      ),
    );
  }

  ListTile _drawerItem({
    required IconData icon,
    required String text,
    Color? color,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.black87),
      title: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      onTap: onTap,
    );
  }
}
