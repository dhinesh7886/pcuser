import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AttendanceDataScreen extends StatefulWidget {
  final String userId;

  const AttendanceDataScreen({super.key, required this.userId});

  @override
  State<AttendanceDataScreen> createState() => _AttendanceDataScreenState();
}

class _AttendanceDataScreenState extends State<AttendanceDataScreen> {
  String? _empName;
  bool _loading = true;

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;

  /// Track expanded state for each date
  final Map<DateTime, bool> _expandedDates = {};

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('id', isEqualTo: widget.userId)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        _empName = snapshot.docs.first['name'] ?? widget.userId;
        await _storeWeekOffSundays();
      } else {
        _empName = widget.userId;
      }
    } catch (e) {
      debugPrint("Error loading user: $e");
      _empName = widget.userId;
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _storeWeekOffSundays() async {
    final startOfMonth = DateTime(_selectedYear, _selectedMonth, 1);
    final endOfMonth = DateTime(
      _selectedMonth == 12 ? _selectedYear + 1 : _selectedYear,
      _selectedMonth == 12 ? 1 : _selectedMonth + 1,
      0,
    );

    final snapshot = await FirebaseFirestore.instance
        .collection("attendance")
        .doc(widget.userId)
        .collection("records")
        .where("timestamp",
            isGreaterThanOrEqualTo: startOfMonth,
            isLessThanOrEqualTo: endOfMonth)
        .get();

    Set<String> existingDates = snapshot.docs.map((doc) {
      final ts = (doc.data()['timestamp'] as Timestamp?)?.toDate();
      if (ts != null) return DateFormat("yyyy-MM-dd").format(ts);
      return "";
    }).toSet();

    for (int day = 1; day <= endOfMonth.day; day++) {
      final date = DateTime(_selectedYear, _selectedMonth, day);
      if (date.weekday == DateTime.sunday) {
        final dateStr = DateFormat("yyyy-MM-dd").format(date);
        if (!existingDates.contains(dateStr)) {
          await FirebaseFirestore.instance
              .collection("attendance")
              .doc(widget.userId)
              .collection("records")
              .add({
            'timestamp': Timestamp.fromDate(date),
            'type': 'week_off',
            'address': 'Week Off',
          });
        }
      }
    }
  }

  Future<Map<DateTime, Map<String, dynamic>>> _fetchAttendance() async {
    final start = DateTime(_selectedYear, _selectedMonth, 1);
    final end = DateTime(
      _selectedMonth == 12 ? _selectedYear + 1 : _selectedYear,
      _selectedMonth == 12 ? 1 : _selectedMonth + 1,
      0,
      23,
      59,
      59,
    );

    final snapshot = await FirebaseFirestore.instance
        .collection("attendance")
        .doc(widget.userId)
        .collection("records")
        .where("timestamp", isGreaterThanOrEqualTo: start)
        .where("timestamp", isLessThanOrEqualTo: end)
        .orderBy("timestamp", descending: false)
        .get();

    Map<DateTime, Map<String, dynamic>> data = {};

    for (var doc in snapshot.docs) {
      final map = doc.data();
      final ts = (map["timestamp"] as Timestamp?)?.toDate();
      if (ts == null) continue;

      final dateKey = DateTime(ts.year, ts.month, ts.day);
      final type = map["type"];
      final address = (map["address"] ?? "Unknown").toString();

      if (!data.containsKey(dateKey)) {
        data[dateKey] = {
          "in": null,
          "out": null,
          "inAddress": null,
          "outAddress": null,
          "type": type,
        };
      }

      if (type == "punch_in") {
        data[dateKey]!["in"] = ts;
        data[dateKey]!["inAddress"] = address;
      }
      if (type == "punch_out") {
        data[dateKey]!["out"] = ts;
        data[dateKey]!["outAddress"] = address;
      }
      if (type == "week_off") data[dateKey]!["type"] = "week_off";
    }

    return data;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text("${_empName ?? widget.userId} (${widget.userId})"),
        centerTitle: true,
        backgroundColor: Colors.indigoAccent,
        elevation: 3,
      ),
      body: Column(
        children: [
          // Year & Month selector
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DropdownButton<int>(
                  value: _selectedYear,
                  borderRadius: BorderRadius.circular(12),
                  dropdownColor: Colors.indigo.shade50,
                  items: List.generate(5, (index) {
                    final year = DateTime.now().year - index;
                    return DropdownMenuItem(
                      value: year,
                      child: Text(
                        year.toString(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87),
                      ),
                    );
                  }),
                  onChanged: (val) =>
                      setState(() => _selectedYear = val!),
                ),
                const SizedBox(width: 16),
                DropdownButton<int>(
                  value: _selectedMonth,
                  borderRadius: BorderRadius.circular(12),
                  dropdownColor: Colors.indigo.shade50,
                  items: List.generate(12, (index) {
                    final month = index + 1;
                    return DropdownMenuItem(
                      value: month,
                      child: Text(
                        DateFormat("MMMM").format(DateTime(0, month)),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87),
                      ),
                    );
                  }),
                  onChanged: (val) =>
                      setState(() => _selectedMonth = val!),
                ),
              ],
            ),
          ),

          Expanded(
            child: FutureBuilder<Map<DateTime, Map<String, dynamic>>>(
              future: _fetchAttendance(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data ?? {};
                int daysInMonth = DateTime(
                  _selectedMonth == 12 ? _selectedYear + 1 : _selectedYear,
                  _selectedMonth == 12 ? 1 : _selectedMonth + 1,
                  0,
                ).day;

                if (_selectedYear == today.year &&
                    _selectedMonth == today.month) {
                  daysInMonth = today.day;
                }

                int present = 0, absent = 0, partial = 0, weekOff = 0;
                List<DateTime> allDates = [];

                for (int i = 1; i <= daysInMonth; i++) {
                  final date = DateTime(_selectedYear, _selectedMonth, i);
                  allDates.add(date);
                  final record = data[date];

                  if (record != null && record["type"] == "week_off") {
                    weekOff++;
                  } else if (record == null) {
                    if (date.weekday == DateTime.sunday) {
                      weekOff++;
                    } else {
                      absent++;
                    }
                  } else if (record["in"] != null && record["out"] != null) {
                    present++;
                  } else {
                    partial++;
                  }
                }

                return Column(
                  children: [
                    // Summary cards
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSummaryCard("Total", daysInMonth,
                                Colors.indigo, Icons.calendar_today),
                            _buildSummaryCard("Present", present, Colors.green,
                                Icons.check_circle),
                            _buildSummaryCard("Partial", partial, Colors.orange,
                                Icons.timelapse),
                            _buildSummaryCard(
                                "Absent", absent, Colors.red, Icons.cancel),
                            _buildSummaryCard("Week Off", weekOff, Colors.grey,
                                Icons.beach_access),
                          ],
                        ),
                      ),
                    ),

                    // Attendance list
                    Expanded(
                      child: ListView.builder(
                        itemCount: allDates.length,
                        itemBuilder: (context, index) {
                          final date = allDates[index];
                          final record = data[date];

                          String punchIn = "-";
                          String punchOut = "-";
                          String punchInAddr = record?["inAddress"] ?? "";
                          String punchOutAddr = record?["outAddress"] ?? "";

                          if (record?["in"] is DateTime) {
                            punchIn = DateFormat("dd MMM yyyy hh:mm a")
                                .format(record!["in"]);
                          }
                          if (record?["out"] is DateTime) {
                            punchOut = DateFormat("dd MMM yyyy hh:mm a")
                                .format(record!["out"]);
                          }

                          // Calculate total & OT hours
                          double totalHours = 0;
                          double otHours = 0;
                          if (record?["in"] != null && record?["out"] != null) {
                            totalHours = record!["out"]
                                    .difference(record["in"])
                                    .inMinutes /
                                60.0;
                            otHours = totalHours > 12 ? totalHours - 12 : 0;
                          }

                          Color statusColor;
                          IconData statusIcon;
                          String statusText;

                          if (record != null &&
                              record["type"] == "week_off") {
                            statusColor = Colors.grey.shade700;
                            statusIcon = Icons.beach_access;
                            statusText = "Week Off";
                          } else if (record == null &&
                              date.weekday == DateTime.sunday) {
                            statusColor = Colors.grey.shade700;
                            statusIcon = Icons.beach_access;
                            statusText = "Week Off";
                          } else if (record == null) {
                            statusColor = Colors.red;
                            statusIcon = Icons.close;
                            statusText = "Absent";
                          } else if (record["in"] != null &&
                              record["out"] != null) {
                            statusColor = Colors.green;
                            statusIcon = Icons.check_circle;
                            statusText = "Present";
                          } else {
                            statusColor = Colors.orange;
                            statusIcon = Icons.timelapse;
                            statusText = "Partial";
                          }

                          final isExpanded = _expandedDates[date] ?? false;

                          return Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 5,
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _expandedDates[date] = !isExpanded;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor:
                                              statusColor.withOpacity(0.15),
                                          child: Icon(statusIcon,
                                              color: statusColor, size: 22),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            DateFormat("dd MMM yyyy (EEE)")
                                                .format(date),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: statusColor,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          isExpanded
                                              ? Icons.keyboard_arrow_up
                                              : Icons.keyboard_arrow_down,
                                          color: Colors.grey,
                                        )
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (statusText == "Week Off")
                                      Text("Week Off",
                                          style: TextStyle(
                                              color: Colors.grey[700]))
                                    else ...[
                                      Text("Punch In: $punchIn"),
                                      Text("Punch Out: $punchOut"),
                                      Text(
                                          "Total Hours: ${totalHours.toStringAsFixed(2)} hrs"),
                                      Text(
                                          "OT Hours: ${otHours.toStringAsFixed(2)} hrs"),
                                      if (isExpanded) ...[
                                        if (punchInAddr.isNotEmpty)
                                          Text("Punch In Location: $punchInAddr"),
                                        if (punchOutAddr.isNotEmpty)
                                          Text(
                                              "Punch Out Location: $punchOutAddr"),
                                      ]
                                    ]
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
      String title, int count, Color color, IconData icon) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.6), color.withOpacity(0.9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            Text(title,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            Text(count.toString(),
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
