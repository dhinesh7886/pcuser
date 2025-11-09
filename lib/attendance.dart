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
      final existingReason = doc.data().containsKey('reason') ? doc['reason'] ?? '' : '';
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

  // ✅ IMPROVED: Only fetch last record, consistent auto-close timestamp/dateKey, avoid duplicates
  Future<void> _determineNextPunchType() async {
    try {
      final now = DateTime.now();
      final todayKey = DateFormat('ddMMyyyy').format(now);
      final recordRef = FirebaseFirestore.instance
          .collection('attendance')
          .doc(widget.userId)
          .collection('records');

      // fetch last record only (more efficient)
      final lastQuery = await recordRef.orderBy('timestamp', descending: true).limit(1).get();
      if (lastQuery.docs.isEmpty) {
        if (mounted) setState(() => nextPunchType = 'punch_in');
        return;
      }

      final lastDoc = lastQuery.docs.first;
      final lastData = lastDoc.data();
      final lastType = lastData['type'] as String?;
      final lastTs = (lastData['timestamp'] as Timestamp?)?.toDate();

      if (lastType == null || lastTs == null) {
        if (mounted) setState(() => nextPunchType = 'punch_in');
        return;
      }

      if (lastType == 'punch_in') {
        final diff = now.difference(lastTs);
        if (diff.inHours >= 24) {
          // Need to auto-close that punch_in at lastTs + 24h
          final autoCloseTs = lastTs.add(const Duration(hours: 24));
          final autoCloseDateKey = DateFormat('ddMMyyyy').format(autoCloseTs);

          // Ensure we don't create duplicate auto-closed records for same timestamp
          final existingAutoClose = await recordRef
              .where('type', isEqualTo: 'punch_out_not_complete')
              .where('autoClosed', isEqualTo: true)
              .where('dateKey', isEqualTo: autoCloseDateKey)
              .get();

          bool duplicate = false;
          for (final d in existingAutoClose.docs) {
            final ts = (d['timestamp'] as Timestamp?)?.toDate();
            if (ts != null && (ts.difference(autoCloseTs).inSeconds).abs() <= 2) {
              duplicate = true;
              break;
            }
          }

          if (!duplicate) {
            await recordRef.add({
              'timestamp': Timestamp.fromDate(autoCloseTs),
              'type': 'punch_out_not_complete',
              'dateKey': autoCloseDateKey,
              'autoClosed': true,
            });
          }

          if (mounted) setState(() => nextPunchType = 'punch_in');
        } else {
          // last punch was recent punch_in -> next should be punch_out
          if (mounted) setState(() => nextPunchType = 'punch_out');
        }
      } else if (lastType == 'punch_out' || lastType == 'punch_out_not_complete') {
        final lastDateKey = DateFormat('ddMMyyyy').format(lastTs);
        // If last punch-out happened today -> attendance completed for today
        if (lastDateKey == todayKey) {
          if (mounted) setState(() => nextPunchType = null);
        } else {
          // last punch-out was on earlier date -> allow punch_in
          if (mounted) setState(() => nextPunchType = 'punch_in');
        }
      } else {
        if (mounted) setState(() => nextPunchType = 'punch_in');
      }
    } catch (e) {
      // on any error default to allowing punch_in
      if (mounted) setState(() => nextPunchType = 'punch_in');
    }
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
      final formattedTime = DateFormat('HH:mm').format(ts);
      if (DateFormat('ddMMyyyy').format(ts) != DateFormat('ddMMyyyy').format(now)) {
        // show date if not today
        final datePart = DateFormat('dd/MM').format(ts);
        timeStr = "$formattedTime ($datePart)";
      } else {
        timeStr = formattedTime;
      }
    }

    final address = data['address'] ?? 'No address';
    final width = MediaQuery.of(context).size.width;

    // Custom label for auto closed
    final type = data['type'];
    String label = (type == 'punch_out_not_complete')
        ? "Punch Out Not Complete"
        : (isPunchIn ? "Punch In" : "Punch Out");

    Color avatarColor;
    IconData avatarIcon;
    if (type == 'punch_out_not_complete') {
      avatarColor = Colors.grey;
      avatarIcon = Icons.error_outline;
    } else {
      avatarColor = isPunchIn ? Colors.green : Colors.red;
      avatarIcon = isPunchIn ? Icons.login : Icons.logout;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.white.withOpacity(0.9),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: avatarColor,
          child: Icon(
            avatarIcon,
            color: Colors.white,
            size: width * 0.07,
          ),
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
