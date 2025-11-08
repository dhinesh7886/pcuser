import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:pcuser/permission_request.dart';
import 'package:pcuser/leave_request.dart';
import 'package:pcuser/attendance_data.dart';
import 'package:pcuser/home.dart';

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
  String? nextPunchType;
  Map<String, dynamic>? _cachedUserData;

  @override
  void initState() {
    super.initState();
    _loadUserDetails();
  }

  Future<void> _loadUserDetails() async {
    try {
      if (_cachedUserData != null) {
        empName = _cachedUserData!['name'];
        companyName = _cachedUserData!['companyName'];
        subDivision = _cachedUserData!['subDivision'];
      } else {
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
          _cachedUserData = data;
        } else {
          empName = "User not found";
        }
      }

      await _checkAndCreateHoliday();
      await _determineNextPunchType();
    } catch (e) {
      empName = "Error loading user";
    } finally {
      if (mounted) setState(() => _loadingUser = false);
    }
  }

  Stream<QuerySnapshot> _todayRecordsStream() {
    final now = DateTime.now();
    final dateKey = DateFormat('ddMMyyyy').format(now);
    return FirebaseFirestore.instance
        .collection('attendance')
        .doc(widget.userId)
        .collection('records')
        .where('dateKey', isEqualTo: dateKey)
        .snapshots();
  }

  Future<void> _checkAndCreateHoliday() async {
    if (companyName == null || subDivision == null) return;
    final now = DateTime.now();
    final dateKey = DateFormat('ddMMyyyy').format(now);

    final holidayMap = {
      'AYCA PC|Corporate': {
        '20102025': 'Deepavali',
        '30102025': 'Month End',
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

    for (final doc in existing.docs) {
      final existingReason = doc['reason'] ?? '';
      if (existingReason != reason) {
        await recordRef.doc(doc.id).delete();
      }
    }

    final stillExists = await recordRef
        .where('dateKey', isEqualTo: dateKey)
        .where('type', isEqualTo: 'holiday')
        .where('reason', isEqualTo: reason)
        .get();

    if (stillExists.docs.isEmpty) {
      await recordRef.add({
        'timestamp': Timestamp.fromDate(now),
        'type': 'holiday',
        'reason': reason,
        'dateKey': dateKey,
        'companyName': companyName,
        'subDivision': subDivision,
      });
    }

    if (mounted) {
      setState(() {
        status =
            "Holiday today: $reason (${DateFormat('dd/MM/yyyy').format(now)})";
      });
    }
  }

  // ✅ UPDATED FUNCTION WITH YOUR LOGIC
  Future<void> _determineNextPunchType() async {
    final now = DateTime.now();
    final recordRef = FirebaseFirestore.instance
        .collection('attendance')
        .doc(widget.userId)
        .collection('records');

    final allRecords = await recordRef.get();
    if (allRecords.docs.isEmpty) {
      if (mounted) setState(() => nextPunchType = 'punch_in');
      return;
    }

    allRecords.docs.sort((a, b) =>
        (b['timestamp'] as Timestamp).compareTo(a['timestamp']));
    final lastRecord = allRecords.docs.first;
    final lastType = lastRecord['type'];
    final lastTime = (lastRecord['timestamp'] as Timestamp).toDate();

    // ⏰ Find today's punch-in/out
    final todayKey = DateFormat('ddMMyyyy').format(now);
    final todayRecords = allRecords.docs
        .where((doc) => doc['dateKey'] == todayKey)
        .toList();

    // 🕐 If last punch was 'in'
    if (lastType == 'punch_in') {
      final diffHours = now.difference(lastTime).inHours.toDouble();

      if (diffHours >= 24) {
        // Auto close after 24 hours
        await recordRef.add({
          'timestamp': Timestamp.fromDate(lastTime.add(const Duration(hours: 24))),
          'type': 'punch_out_not_complete',
          'dateKey': DateFormat('ddMMyyyy').format(lastTime),
          'autoClosed': true,
        });
        nextPunchType = 'punch_in';
      } else {
        nextPunchType = 'punch_out';
      }
    } else if (lastType == 'punch_out') {
      final lastDate = DateFormat('ddMMyyyy').format(lastTime);
      final sameDay = lastDate == todayKey;

      if (sameDay) {
        // ❌ Already punched out today — block another punch-in
        nextPunchType = null;
      } else {
        // ✅ If last punch-out was from a cross-day shift (<24h difference)
        final diffHours = now.difference(lastTime).inHours.toDouble();
        if (diffHours < 24) {
          nextPunchType = 'punch_in';
        } else {
          nextPunchType = 'punch_in';
        }
      }
    } else {
      nextPunchType = 'punch_in';
    }

    if (mounted) setState(() {});
  }

  Future<Map<String, dynamic>> _getAccurateLocation() async {
    Position? position;
    for (int i = 0; i < 3; i++) {
      position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation);
      if (position.accuracy <= 20) break;
      await Future.delayed(const Duration(seconds: 2));
    }

    if (position == null) throw Exception("Unable to fetch location.");

    final placemarks =
        await placemarkFromCoordinates(position.latitude, position.longitude);
    if (placemarks.isEmpty) throw Exception("Unable to fetch address.");

    final p = placemarks.first;
    final components = [
      p.name,
      p.street,
      p.subLocality,
      p.locality,
      p.administrativeArea,
      p.postalCode,
      p.country
    ];
    String address = components
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(', ');

    return {
      "latitude": position.latitude,
      "longitude": position.longitude,
      "address": address
    };
  }

  Future<void> _markAttendance() async {
    if (saving || nextPunchType == null) return;

    setState(() {
      saving = true;
      status = "Marking attendance...";
      showRetry = false;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception("Location services disabled.");

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception("Location permission denied.");
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception("Location permanently denied.");
      }

      final now = DateTime.now();
      final dateKey = DateFormat('ddMMyyyy').format(now);
      final locationData = await _getAccurateLocation();

      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(widget.userId)
          .collection('records')
          .add({
        'timestamp': Timestamp.fromDate(now),
        'lat': locationData["latitude"],
        'lng': locationData["longitude"],
        'address': locationData["address"],
        'type': nextPunchType,
        'dateKey': dateKey,
        'holidayName': todayHolidayName,
      });

      if (mounted) {
        setState(() {
          String displayTime = DateFormat('HH:mm').format(now);
          status =
              "${nextPunchType == 'punch_in' ? "Punch In" : "Punch Out"} saved at $displayTime\n${locationData["address"]}";
        });
        await _determineNextPunchType();
      }
    } catch (e) {
      setState(() {
        status = "Error: $e";
        showRetry = true;
      });
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    final title =
        _loadingUser ? "Loading..." : "${empName ?? widget.userId} - ${widget.userId}";

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        backgroundColor: Colors.teal,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const UsersHomePage()),
            );
          },
        ),
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
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(),
                const SizedBox(height: 12),
                const Divider(color: Colors.white70, thickness: 1),
                const Text("Today's Records",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 8),
                _buildRecordsList(),
                const SizedBox(height: 12),
                _fullWidthButton(
                    icon: Icons.request_page,
                    label: "Permission Request",
                    color: Colors.orange,
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  PermissionRequestScreen(userId: widget.userId)));
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (nextPunchType == null || saving) ? null : _markAttendance,
        icon: const Icon(Icons.fingerprint),
        label: Text(
          nextPunchType == null
              ? "Attendance Completed"
              : nextPunchType == 'punch_in'
                  ? "Punch In"
                  : "Punch Out",
          style: const TextStyle(fontSize: 15),
        ),
        backgroundColor: nextPunchType == null
            ? const Color.fromARGB(255, 248, 195, 195)
            : const Color.fromARGB(255, 240, 217, 87),
      ),
    );
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
          Text(status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black87)),
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
                label: const Text("Retry",
                    style: TextStyle(color: Colors.white)),
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
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text(
              todayHolidayName != null
                  ? "Holiday: $todayHolidayName"
                  : "No attendance marked today",
              style: const TextStyle(color: Colors.white),
            ),
          );
        }

        final sortedDocs = docs.toList()
          ..sort((a, b) =>
              (a['timestamp'] as Timestamp).compareTo((b['timestamp'] as Timestamp)));

        return Column(
          children: sortedDocs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final type = data['type'];
            if (type == 'holiday') return _buildHolidayCard(data);
            return _buildRecordCard(data, type == 'punch_in');
          }).toList(),
        );
      },
    );
  }

  Widget _buildHolidayCard(Map<String, dynamic> data) {
    final reason = data['reason'] ?? 'Holiday';
    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    final dateStr = ts != null ? DateFormat('dd/MM/yyyy').format(ts) : '';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.yellow.shade200,
      child: ListTile(
        leading: const Icon(Icons.beach_access, color: Colors.orange),
        title: Text("Holiday: $reason"),
        subtitle: Text(dateStr),
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> data, bool isPunchIn) {
    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    String timeStr = 'Pending';
    if (ts != null) {
      final now = DateTime.now();
      int hour = ts.hour;
      if (ts.day > now.day) hour += 24;
      final formattedHour = hour.toString().padLeft(2, '0');
      final formattedMin = ts.minute.toString().padLeft(2, '0');
      timeStr = "$formattedHour:$formattedMin";
    }

    final address = data['address'] ?? 'No address';
    final width = MediaQuery.of(context).size.width;

    // Custom label for auto closed
    final type = data['type'];
    String label = (type == 'punch_out_not_complete')
        ? "Punch Out Not Complete"
        : (isPunchIn ? "Punch In" : "Punch Out");

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.white.withOpacity(0.9),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: type == 'punch_out_not_complete'
              ? Colors.grey
              : (isPunchIn ? Colors.green : Colors.red),
          child: Icon(
              type == 'punch_out_not_complete'
                  ? Icons.error_outline
                  : (isPunchIn ? Icons.login : Icons.logout),
              color: Colors.white,
              size: width * 0.07),
        ),
        title: Text("$label • $timeStr",
            style: TextStyle(fontSize: width * 0.045)),
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
              borderRadius: BorderRadius.circular(15)),
        ),
        icon: Icon(icon, color: Colors.white, size: width * 0.06),
        label: Text(label,
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: width * 0.045)),
        onPressed: onTap,
      ),
    );
  }
}
