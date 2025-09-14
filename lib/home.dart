import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:pcuser/attendance.dart';
import 'package:pcuser/bookings.dart';
import 'package:pcuser/home_widget.dart';
import 'package:pcuser/login_page.dart';
import 'package:pcuser/profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final id = prefs.getString('id'); // empId saved during login
    if (id != null) {
      final snapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('id', isEqualTo: id) // Firestore field is 'id'
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
    List<Widget> screens = [
      const HomeWidget(),
      const CabBookingPage(),
      empId == null
          ? const Center(child: CircularProgressIndicator())
          : AttendanceScreen(userId: empId!),
    ];

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 171, 243, 236),
      appBar: widget.isShowAppBar
          ? AppBar(
              title: const Text('PC Users'),
              backgroundColor: const Color.fromARGB(255, 247, 126, 227),
              actions: [
                IconButton(
                  onPressed: () async {
                    List<Location> locations = await locationFromAddress(
                      "Tirunelveli",
                    );
                    for (var element in locations) {
                      debugPrint(element.toString());
                    }
                  },
                  icon: const Icon(Icons.location_city),
                ),
              ],
            )
          : null,
      drawer: Drawer(
        child: empId == null
            ? const Center(child: Text("Employee ID not found"))
            : userData == null
                ? const Center(child: Text("No user profile found"))
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      DrawerHeader(
                        decoration: const BoxDecoration(
                          color: Colors.deepPurple,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userData!['name'] ?? 'PC User',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            CircleAvatar(
                              radius: 30,
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
                          ],
                        ),
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.person,
                          color: Colors.purple,
                        ),
                        title: const Text('Profile'),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const ProfilePage(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.book_online_outlined),
                        title: const Text('Attendance'),
                        onTap: () {
                          if (empId != null) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    AttendanceScreen(userId: empId!),
                              ),
                            );
                          }
                        },
                      ),
                      const ListTile(
                        leading: Icon(Icons.history),
                        title: Text('Previous Trips'),
                      ),
                      const ListTile(
                        leading: Icon(Icons.upcoming),
                        title: Text('Upcoming Trips'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.logout, color: Colors.red),
                        title: const Text('Signout'),
                        onTap: () async {
                          await FirebaseAuth.instance.signOut();
                          final prefs =
                              await SharedPreferences.getInstance();
                          await prefs.remove('id');
                          if (!mounted) return;
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) =>
                                  const StylishLoginPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: screenIndex,
        onTap: (value) {
          if (value != screenIndex) {
            setState(() {
              screenIndex = value;
            });
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_taxi),
            label: "Booking",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark_added_rounded),
            label: "Attendance",
          ),
        ],
      ),
      body: screens[screenIndex],
    );
  }
}
