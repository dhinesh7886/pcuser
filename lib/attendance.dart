import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:pcuser/permission_request.dart';
import 'package:pcuser/leave_request.dart';
import 'package:pcuser/attendance_data.dart';
import 'dart:async';

class AttendanceScreen extends StatefulWidget {
  final String userId;
  const AttendanceScreen({super.key, required this.userId});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool saving = false;
  String status = "Tap the button to mark attendance";
  bool showRetry = false;
  String? empName;
  String? companyName;
  String? subDivision;
  bool _loadingUser = true;
  String? todayHolidayName;

  @override
  void initState() {
    super.initState();
    _loadUserDetails();
  }

  Future<void> _loadUserDetails() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('id', isEqualTo: widget.userId)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        empName = data['name'] ?? widget.userId;
        companyName = data['companyName'];
        subDivision = data['subDivision'];
      } else {
        empName = "User not found";
      }

      await _checkAndCreateHoliday();
    } catch (e) {
      empName = "Error loading user";
    } finally {
      if (mounted) setState(() => _loadingUser = false);
    }
  }

  DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day).add(const Duration(days: 1));

  Stream<QuerySnapshot> _todayRecordsStream() {
    final now = DateTime.now();
    return FirebaseFirestore.instance
        .collection('attendance')
        .doc(widget.userId)
        .collection('records')
        .where('timestamp', isGreaterThanOrEqualTo: _startOfDay(now))
        .where('timestamp', isLessThan: _endOfDay(now))
        .orderBy('timestamp')
        .snapshots();
  }

  Stream<QuerySnapshot> _allRecordsStream() {
    return FirebaseFirestore.instance
        .collection('attendance')
        .doc(widget.userId)
        .collection('records')
        .orderBy('timestamp')
        .snapshots();
  }

  Future<void> _checkAndCreateHoliday() async {
    if (companyName == null || subDivision == null) return;

    final now = DateTime.now();
    final dateKey = DateFormat('ddMMyyyy').format(now);

    final holidayMap = {
      'AYCA PC|Corporate': {
        '20102025': 'Deepavali',
        '25122025': 'Christmas',
      },
      'AYCA PC|Isuzu': {
        '20102025': 'Diwali',
        '21102025': 'Additional Holiday for Diwali',
        '25122025': 'Christmas',
      },
    };

    final key = '$companyName|$subDivision';
    final holidays = holidayMap[key];

    if (holidays == null || !holidays.containsKey(dateKey)) return;

    final reason = holidays[dateKey]!;
    todayHolidayName = reason;

    final recordRef = FirebaseFirestore.instance
        .collection('attendance')
        .doc(widget.userId)
        .collection('records');

    final existing = await recordRef
        .where('dateKey', isEqualTo: dateKey)
        .where('type', isEqualTo: 'holiday')
        .get();

    if (existing.docs.isEmpty) {
      await recordRef.add({
        'timestamp': Timestamp.fromDate(now),
        'type': 'holiday',
        'reason': reason,
        'dateKey': dateKey,
        'companyName': companyName,
        'subDivision': subDivision,
      });

      if (mounted) {
        setState(() {
          status =
              "Holiday today: $reason (${DateFormat('dd/MM/yyyy').format(now)})";
        });
      }
    }
  }

  Future<void> _markAttendance() async {
    if (saving) return;
    setState(() {
      saving = true;
      status = "Marking attendance...";
      showRetry = false;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          status = "Location services are disabled.";
          showRetry = true;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            status = "Location permission denied.";
            showRetry = true;
          });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          status = "Location permanently denied.";
          showRetry = true;
        });
        return;
      }

      final now = DateTime.now();
      DateTime adjustedDate = now;
      if (now.hour < 5) {
        adjustedDate = now.subtract(const Duration(days: 1));
      }

      final dateKey = DateFormat('ddMMyyyy').format(adjustedDate);

      final lastRecordSnapshot = await FirebaseFirestore.instance
          .collection('attendance')
          .doc(widget.userId)
          .collection('records')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      final lastRecord =
          lastRecordSnapshot.docs.isNotEmpty ? lastRecordSnapshot.docs.first : null;

      String type;

      // NIGHT SHIFT LOGIC
      if (lastRecord != null && lastRecord['type'] == 'punch_in') {
        final lastPunchTime = (lastRecord['timestamp'] as Timestamp).toDate();
        final fiveAMToday = DateTime(lastPunchTime.year,
            lastPunchTime.month, lastPunchTime.day + 1, 5, 0, 0);
        if (now.isBefore(fiveAMToday)) {
          type = 'punch_out'; // Allow punch out for previous day
        } else {
          type = 'punch_in'; // After 5AM, treat as new day punch in
        }
      } else {
        type = (lastRecord != null && lastRecord['type'] == 'punch_out')
            ? 'punch_in'
            : 'punch_in';
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
        ).timeout(const Duration(seconds: 30));
      } on TimeoutException {
        setState(() {
          status = "Location lookup timed out, using last known position...";
        });
        pos = await Geolocator.getLastKnownPosition();
        if (pos == null) {
          setState(() {
            status = "Unable to get location, please try again.";
            showRetry = true;
          });
          return;
        }
      }

      String address = "Unknown location";
      try {
        final placemarks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          address = [
            p.name,
            p.street,
            p.locality,
            p.administrativeArea,
            p.country
          ].whereType<String>().where((e) => e.trim().isNotEmpty).join(', ');
        }
      } catch (_) {
        address = "Unable to fetch address";
      }

      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(widget.userId)
          .collection('records')
          .add({
        'timestamp': Timestamp.fromDate(now),
        'adjustedDate': Timestamp.fromDate(adjustedDate),
        'lat': pos.latitude,
        'lng': pos.longitude,
        'address': address,
        'type': type,
        'dateKey': dateKey,
        'holidayName': todayHolidayName,
      });

      if (mounted) {
        setState(() {
          status =
              "${type == 'punch_in' ? "Punch In" : "Punch Out"} saved at ${DateFormat('HH:mm').format(now)}\n$address";
          showRetry = false;
        });
      }
    } catch (e) {
      setState(() {
        status = "Error saving attendance: $e";
        showRetry = true;
      });
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Text(
            status,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black87),
          ),
          if (showRetry)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ElevatedButton.icon(
                onPressed: _markAttendance,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text(
                  "Retry",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecordsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _todayRecordsStream(),
      builder: (context, snapshot) {
        if (_loadingUser) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text("No attendance marked today",
                style: TextStyle(color: Colors.white)),
          );
        }

        final docs = snapshot.data!.docs;

        return SingleChildScrollView(
          child: Column(
            children: docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final type = data['type'];
              if (type == 'holiday') return _buildHolidayCard(doc);
              return _buildRecordCard(
                  doc, type == 'punch_in' ? true : false);
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildHolidayCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final reason = data['reason'] ?? 'Holiday';
    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    final dateStr = ts != null ? DateFormat('dd/MM/yyyy').format(ts) : '';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.yellow.shade100,
      child: ListTile(
        leading: const Icon(Icons.beach_access, color: Colors.orange),
        title: Text("Holiday: $reason"),
        subtitle: Text(dateStr),
      ),
    );
  }

  Widget _buildRecordCard(QueryDocumentSnapshot doc, bool isPunchIn) {
    final data = doc.data() as Map<String, dynamic>;
    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    final timeStr = ts != null ? DateFormat('HH:mm').format(ts) : 'Pending';
    final address = data['address'] ?? 'No address';
    final holidayName = data['holidayName'];
    final width = MediaQuery.of(context).size.width;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.white.withOpacity(0.9),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isPunchIn ? Colors.green : Colors.red,
          child: Icon(
            isPunchIn ? Icons.login : Icons.logout,
            color: Colors.white,
            size: width * 0.07,
          ),
        ),
        title: Text(
          "${isPunchIn ? "Punch In" : "Punch Out"} • $timeStr" +
              (holidayName != null ? " • $holidayName" : ""),
          style: TextStyle(fontSize: width * 0.045),
        ),
        subtitle: Text(address, style: TextStyle(fontSize: width * 0.035)),
      ),
    );
  }

  Widget _fullWidthButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    double width = MediaQuery.of(context).size.width;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04, vertical: 8),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          minimumSize: Size(double.infinity, width * 0.14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        icon: Icon(icon, color: Colors.white, size: width * 0.06),
        label: Text(
          label,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: width * 0.045),
        ),
        onPressed: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _loadingUser ? "Loading..." : (empName ?? widget.userId);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        backgroundColor: Colors.teal,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00BFA6), Color(0xFF00E5FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white70, thickness: 1),
                  const Text(
                    "Today's Records",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  SizedBox(
                      height: MediaQuery.of(context).size.height * 0.45,
                      child: _buildRecordsList()),
                  _fullWidthButton(
                      icon: Icons.request_page,
                      label: "Permission Request",
                      color: Colors.orange,
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => PermissionRequestScreen(
                                    userId: widget.userId)));
                      }),
                  _fullWidthButton(
                      icon: Icons.leave_bags_at_home,
                      label: "Leave Request",
                      color: Colors.blue,
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    LeaveRequestScreen(userId: widget.userId)));
                      }),
                  _fullWidthButton(
                      icon: Icons.data_usage,
                      label: "Attendance Data",
                      color: Colors.green,
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    AttendanceDataScreen(userId: widget.userId)));
                      }),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: StreamBuilder<QuerySnapshot>(
        stream: _allRecordsStream(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          QueryDocumentSnapshot? lastPunch;
          try {
            lastPunch = docs.lastWhere(
              (d) => d['type'] == 'punch_in' || d['type'] == 'punch_out',
            );
          } catch (e) {
            lastPunch = null;
          }

          String label;
          if (lastPunch != null && lastPunch['type'] == 'punch_in') {
            final lastPunchTime =
                (lastPunch['timestamp'] as Timestamp).toDate();
            final fiveAMToday = DateTime(lastPunchTime.year,
                lastPunchTime.month, lastPunchTime.day + 1, 5, 0, 0);
            if (DateTime.now().isBefore(fiveAMToday)) {
              label = "Punch Out";
            } else {
              label = "Punch In";
            }
          } else {
            label = (lastPunch == null || lastPunch['type'] == 'punch_out')
                ? "Punch In"
                : "Punch Out";
          }

          return FloatingActionButton.extended(
            onPressed: saving ? null : _markAttendance,
            icon: const Icon(Icons.fingerprint),
            label: Text(label),
            backgroundColor: const Color.fromARGB(255, 240, 217, 87),
          );
        },
      ),
    );
  }
}
