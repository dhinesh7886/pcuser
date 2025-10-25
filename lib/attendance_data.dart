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

  DateTime? _startDate;
  DateTime? _endDate;

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

  Future<Map<DateTime, Map<String, dynamic>>> _fetchAttendance() async {
    if (_startDate == null || _endDate == null) return {};

    final snapshot = await FirebaseFirestore.instance
        .collection("attendance")
        .doc(widget.userId)
        .collection("records")
        .where("timestamp", isGreaterThanOrEqualTo: _startDate!)
        .where("timestamp", isLessThanOrEqualTo: _endDate!)
        .orderBy("timestamp")
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

  String _formatHoursToHHMM(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}";
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(_startDate!)) {
          _endDate = _startDate;
        }
        _expandedDates.clear();
      });
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
        _expandedDates.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("${_empName ?? widget.userId} (${widget.userId})"),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(255, 163, 245, 125),
        elevation: 3,
      ),
      body: Column(
        children: [
          // Date range selection fields
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: "Start Date",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    controller: TextEditingController(
                        text: _startDate != null
                            ? DateFormat("dd MMM yyyy").format(_startDate!)
                            : ""),
                    onTap: _selectStartDate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: "End Date",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    controller: TextEditingController(
                        text: _endDate != null
                            ? DateFormat("dd MMM yyyy").format(_endDate!)
                            : ""),
                    onTap: _selectEndDate,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _startDate == null || _endDate == null
                ? const Center(
                    child: Text("Select start and end date to view attendance"))
                : FutureBuilder<Map<DateTime, Map<String, dynamic>>>(
                    future: _fetchAttendance(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(child: Text("Error: ${snapshot.error}"));
                      }

                      final data = snapshot.data ?? {};
                      if (data.isEmpty) {
                        return const Center(child: Text("No attendance found"));
                      }

                      int present = 0, absent = 0, partial = 0, weekOff = 0;
                      double totalPeriodHours = 0;
                      double totalPeriodOT = 0;

                      List<DateTime> allDates = [];
                      for (DateTime date = _startDate!;
                          !date.isAfter(_endDate!);
                          date = date.add(const Duration(days: 1))) {
                        allDates.add(date);
                        final record = data[date];

                        DateTime? punchInTime = record?["in"] as DateTime?;
                        DateTime? punchOutTime = record?["out"] as DateTime?;

                        double totalHours = 0;
                        double otHours = 0;

                        if (punchInTime != null && punchOutTime != null) {
                          totalHours =
                              punchOutTime.difference(punchInTime).inMinutes /
                                  60.0;
                          otHours = totalHours > 12 ? totalHours - 12 : 0;

                          totalPeriodHours += totalHours;
                          totalPeriodOT += otHours;
                        }

                        if (record != null && record["type"] == "week_off") {
                          weekOff++;
                        } else if (record == null) {
                          if (date.weekday == DateTime.sunday) {
                            weekOff++;
                          } else {
                            absent++;
                          }
                        } else if (punchInTime != null && punchOutTime != null) {
                          present++;
                        } else {
                          partial++;
                        }
                      }

                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildSummaryCard(
                                    "Total Days",
                                    allDates.length,
                                    Colors.indigo,
                                    Icons.calendar_today,
                                    isTablet),
                                _buildSummaryCard(
                                    "Present", present, Colors.green, Icons.check_circle, isTablet),
                                _buildSummaryCard(
                                    "Partial", partial, Colors.orange, Icons.timelapse, isTablet),
                                _buildSummaryCard(
                                    "Absent", absent, Colors.red, Icons.cancel, isTablet),
                                _buildSummaryCard(
                                    "Week Off", weekOff, Colors.grey, Icons.beach_access, isTablet),
                                _buildSummaryCard(
                                    "Total Hrs", 0, Colors.blue, Icons.access_time, isTablet,
                                    hours: totalPeriodHours),
                                _buildSummaryCard(
                                    "OT Hrs", 0, Colors.deepPurple, Icons.timelapse, isTablet,
                                    hours: totalPeriodOT),
                              ],
                            ),
                          ),

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

                                DateTime? punchInTime = record?["in"] as DateTime?;
                                DateTime? punchOutTime = record?["out"] as DateTime?;

                                double totalHours = 0;
                                double otHours = 0;

                                if (punchInTime != null) {
                                  punchIn = DateFormat("dd MMM yyyy hh:mm a")
                                      .format(punchInTime);
                                }
                                if (punchOutTime != null) {
                                  punchOut = DateFormat("dd MMM yyyy hh:mm a")
                                      .format(punchOutTime);
                                }

                                if (punchInTime != null && punchOutTime != null) {
                                  totalHours =
                                      punchOutTime.difference(punchInTime).inMinutes / 60.0;
                                  otHours = totalHours > 12 ? totalHours - 12 : 0;
                                }

                                Color statusColor;
                                IconData statusIcon;
                                String statusText;

                                if (record != null && record["type"] == "week_off") {
                                  statusColor = Colors.grey.shade700;
                                  statusIcon = Icons.beach_access;
                                  statusText = "Week Off";
                                } else if (record == null && date.weekday == DateTime.sunday) {
                                  statusColor = Colors.grey.shade700;
                                  statusIcon = Icons.beach_access;
                                  statusText = "Week Off";
                                } else if (record == null) {
                                  statusColor = Colors.red;
                                  statusIcon = Icons.close;
                                  statusText = "Absent";
                                } else if (punchInTime != null && punchOutTime != null) {
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
                                                radius: isTablet ? 26 : 22,
                                                backgroundColor:
                                                    statusColor.withOpacity(0.15),
                                                child: Icon(statusIcon,
                                                    color: statusColor,
                                                    size: isTablet ? 26 : 22),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  DateFormat("dd MMM yyyy (EEE)")
                                                      .format(date),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: isTablet ? 16 : 15,
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
                                                "Total Hours: ${_formatHoursToHHMM(totalHours)}"),
                                            Text(
                                                "OT Hours: ${_formatHoursToHHMM(otHours)}"),
                                            if (isExpanded) ...[
                                              if (punchInAddr.isNotEmpty)
                                                Text("Punch In Location: $punchInAddr"),
                                              if (punchOutAddr.isNotEmpty)
                                                Text("Punch Out Location: $punchOutAddr"),
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

  Widget _buildSummaryCard(String title, int count, Color color,
      IconData icon, bool isTablet,
      {double? hours}) {
    String displayText = hours != null ? _formatHoursToHHMM(hours) : count.toString();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: isTablet ? 120 : 100,
        padding: EdgeInsets.all(isTablet ? 14 : 10),
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
            Icon(icon, color: Colors.white, size: isTablet ? 28 : 24),
            SizedBox(height: isTablet ? 6 : 4),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: isTablet ? 15 : 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            Text(displayText,
                style: TextStyle(
                    fontSize: isTablet ? 18 : 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
