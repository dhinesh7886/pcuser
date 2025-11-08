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
  String? _companyName;
  String? _subDivision;
  bool _loading = true;

  DateTime? _startDate;
  DateTime? _endDate;

  final Map<DateTime, bool> _expandedDates = {};

  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserNameAndOrg();
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _loadUserNameAndOrg() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('id', isEqualTo: widget.userId)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        _empName = doc['name'] ?? widget.userId;
        _companyName = doc['companyName'];
        _subDivision = doc['subDivision'];
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

  /// Modified fetch: group late-night timestamps (hour < 5) to previous day
  Future<Map<DateTime, Map<String, dynamic>>> _fetchAttendance() async {
    if (_startDate == null || _endDate == null) return {};

    DateTime start =
        DateTime(_startDate!.year, _startDate!.month, _startDate!.day, 0, 0, 0);
    DateTime end =
        DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);

    final Map<DateTime, Map<String, dynamic>> data = {};

    // 1) Fetch attendance records
    final snapshot = await FirebaseFirestore.instance
        .collection("attendance")
        .doc(widget.userId)
        .collection("records")
        .where("timestamp", isGreaterThanOrEqualTo: start)
        .where("timestamp", isLessThanOrEqualTo: end)
        .orderBy("timestamp")
        .get();

    for (var doc in snapshot.docs) {
      final map = doc.data();
      final ts = (map["timestamp"] as Timestamp?)?.toDate();
      if (ts == null) continue;

      // --- NEW: compute workingDate (if time < 05:00 treat as previous day) ---
      DateTime workingDateCandidate =
          DateTime(ts.year, ts.month, ts.day); // by timestamp date
      DateTime workingDate;
      if (ts.hour < 5) {
        // assign to previous day
        final prev = workingDateCandidate.subtract(const Duration(days: 1));
        workingDate = DateTime(prev.year, prev.month, prev.day);
      } else {
        workingDate = DateTime(workingDateCandidate.year, workingDateCandidate.month,
            workingDateCandidate.day);
      }
      // -----------------------------------------------------------------------

      final type = map["type"];
      final address = (map["address"] ?? "").toString();

      data.putIfAbsent(workingDate, () => {
            "in": null,
            "out": null,
            "inAddress": null,
            "outAddress": null,
            "type": null,
            "holidayName": null,
          });

      // Note: we keep the actual timestamps as stored; grouping is done by workingDate.
      if (type == "punch_in") {
        // If multiple punch_ins occur, keep the earliest for that workingDate (if desired)
        final existingIn = data[workingDate]!["in"] as DateTime?;
        if (existingIn == null || ts.isBefore(existingIn)) {
          data[workingDate]!["in"] = ts;
          data[workingDate]!["inAddress"] = address;
        }
      } else if (type == "punch_out") {
        // Keep latest punch_out for that workingDate
        final existingOut = data[workingDate]!["out"] as DateTime?;
        if (existingOut == null || ts.isAfter(existingOut)) {
          data[workingDate]!["out"] = ts;
          data[workingDate]!["outAddress"] = address;
        }
      } else if (type == "week_off" || type == "holiday") {
        data[workingDate]!["type"] = type;
      }
    }

    // 2) Fetch holidays from Firestore
    final holidaySnap = await FirebaseFirestore.instance
        .collection("holidays")
        .where("date", isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where("date", isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();

    for (var doc in holidaySnap.docs) {
      final hData = doc.data();
      final hDate = (hData["date"] as Timestamp?)?.toDate();
      if (hDate == null) continue;
      final dateKey = DateTime(hDate.year, hDate.month, hDate.day);
      data.putIfAbsent(dateKey, () => {
            "in": null,
            "out": null,
            "inAddress": null,
            "outAddress": null,
            "type": null,
            "holidayName": null,
          });
      data[dateKey]!["type"] = "holiday";
      data[dateKey]!["holidayName"] = hData["name"] ?? "Holiday";
    }

    // 3) Local holidayMap
    final localHolidayMap = {
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

    if (_companyName != null && _subDivision != null) {
      final key = '$_companyName|$_subDivision';
      final companyHolidays = localHolidayMap[key];
      if (companyHolidays != null && companyHolidays.isNotEmpty) {
        companyHolidays.forEach((dateStr, reason) {
          try {
            if (dateStr.length == 8) {
              final dd = int.parse(dateStr.substring(0, 2));
              final mm = int.parse(dateStr.substring(2, 4));
              final yyyy = int.parse(dateStr.substring(4, 8));
              final d = DateTime(yyyy, mm, dd);
              if (!d.isBefore(start) && !d.isAfter(end)) {
                final dateKey = DateTime(d.year, d.month, d.day);
                data.putIfAbsent(dateKey, () => {
                      "in": null,
                      "out": null,
                      "inAddress": null,
                      "outAddress": null,
                      "type": null,
                      "holidayName": null,
                    });
                if (data[dateKey]!["holidayName"] == null ||
                    (data[dateKey]!["holidayName"] as String).isEmpty) {
                  data[dateKey]!["type"] = "holiday";
                  data[dateKey]!["holidayName"] = reason;
                } else {
                  if ((data[dateKey]!["holidayName"] as String) != reason) {
                    data[dateKey]!["holidayName"] =
                        "${data[dateKey]!["holidayName"]} (${reason})";
                  }
                }
              }
            }
          } catch (_) {}
        });
      }
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
        _startDateController.text = DateFormat("dd MMM yyyy").format(picked);
        if (_endDate != null && _endDate!.isBefore(_startDate!)) {
          _endDate = _startDate;
          _endDateController.text = DateFormat("dd MMM yyyy").format(_endDate!);
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
        _endDateController.text = DateFormat("dd MMM yyyy").format(picked);
        _expandedDates.clear();
      });
    }
  }

  /// Helper to format punch times; if time.hour < 5 show 24+ style
  String _displayTimeWith27Style(DateTime ts) {
    if (ts.hour < 5) {
      final hour = 24 + ts.hour;
      final minute = ts.minute.toString().padLeft(2, '0');
      return "$hour:$minute";
    } else {
      return DateFormat("dd MMM yyyy hh:mm a").format(ts);
    }
  }

  /// Helper to format only HH:mm with 24+ style for night shifts
  String _displayTimeHHmm(DateTime ts) {
    if (ts.hour < 5) {
      final hour = 24 + ts.hour;
      final minute = ts.minute.toString().padLeft(2, '0');
      return "$hour:$minute";
    } else {
      return DateFormat("HH:mm").format(ts);
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
      ),
      body: Column(
        children: [
          // Date selectors
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _startDateController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: "Start Date",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    onTap: _selectStartDate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _endDateController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: "End Date",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    onTap: _selectEndDate,
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: (_startDate == null || _endDate == null)
                ? const Center(
                    child: Text("Select start and end date to view attendance"))
                : FutureBuilder<Map<DateTime, Map<String, dynamic>>>(
                    future: _fetchAttendance(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text("Error: ${snapshot.error}"));
                      }

                      final data = snapshot.data ?? {};
                      List<DateTime> allDates = [];
                      for (DateTime date = _startDate!;
                          !date.isAfter(_endDate!);
                          date = date.add(const Duration(days: 1))) {
                        allDates.add(date);
                      }

                      int present = 0,
                          absent = 0,
                          partial = 0,
                          weekOff = 0,
                          workedWeekOff = 0,
                          holidays = 0;
                      double totalPeriodHours = 0;
                      double totalPeriodOT = 0;

                      for (var date in allDates) {
                        final record = data[date];
                        DateTime? punchInTime = record?["in"] as DateTime?;
                        DateTime? punchOutTime = record?["out"] as DateTime?;
                        String? type = record?["type"];
                        bool isWeekOff =
                            type == "week_off" || date.weekday == DateTime.sunday;
                        bool isHoliday = type == "holiday";
                        bool hasPunch = punchInTime != null || punchOutTime != null;

                        if (punchInTime != null && punchOutTime != null) {
                          // If punchOut is before punchIn (rare), assume next day
                          DateTime adjustedPunchOut = punchOutTime;
                          if (punchOutTime.isBefore(punchInTime)) {
                            adjustedPunchOut =
                                punchOutTime.add(const Duration(days: 1));
                          }
                          final totalHours =
                              adjustedPunchOut.difference(punchInTime).inMinutes /
                                  60.0;
                          totalPeriodHours += totalHours;
                          totalPeriodOT += totalHours > 12 ? totalHours - 12 : 0;
                        }

                        if (isHoliday) {
                          holidays++;
                        } else if (isWeekOff && hasPunch) {
                          workedWeekOff++;
                        } else if (isWeekOff) {
                          weekOff++;
                        } else if (!hasPunch) {
                          absent++;
                        } else if (punchInTime != null && punchOutTime != null) {
                          present++;
                        } else {
                          partial++;
                        }
                      }

                      return SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Summary cards
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: Row(
                                  children: [
                                    _buildSummaryCard("Total Days", allDates.length,
                                        Colors.indigo, Icons.calendar_today, isTablet),
                                    _buildSummaryCard("Present", present, Colors.green,
                                        Icons.check_circle, isTablet),
                                    _buildSummaryCard("Partial", partial, Colors.orange,
                                        Icons.timelapse, isTablet),
                                    _buildSummaryCard("Absent", absent, Colors.red,
                                        Icons.cancel, isTablet),
                                    _buildSummaryCard("Week Off", weekOff, Colors.grey,
                                        Icons.beach_access, isTablet),
                                    _buildSummaryCard("Worked on WeekOff", workedWeekOff,
                                        Colors.blue, Icons.work, isTablet),
                                    _buildSummaryCard("Holiday", holidays, Colors.purple,
                                        Icons.celebration, isTablet),
                                    _buildSummaryCard("Total Hrs", 0, Colors.blueAccent,
                                        Icons.access_time, isTablet,
                                        hours: totalPeriodHours),
                                    _buildSummaryCard("OT Hrs", 0, Colors.deepPurple,
                                        Icons.timelapse, isTablet,
                                        hours: totalPeriodOT),
                                  ],
                                ),
                              ),

                              // Day list
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: allDates.length,
                                itemBuilder: (context, index) {
                                  final date = allDates[index];
                                  final record = data[date];

                                  DateTime? punchInTime =
                                      record?["in"] as DateTime?;
                                  DateTime? punchOutTime =
                                      record?["out"] as DateTime?;
                                  String? holidayName =
                                      record?["holidayName"] as String?;
                                  String? type = record?["type"] as String?;

                                  // Display strings:
                                  String punchIn = punchInTime != null
                                      ? DateFormat("dd MMM yyyy hh:mm a")
                                          .format(punchInTime)
                                      : "-";

                                  String punchOut = "-";
                                  if (punchOutTime != null) {
                                    // If this punchOut belongs to after-midnight (<5), show 24+ format for time only.
                                    if (punchOutTime.hour < 5) {
                                      // show just time in 24+ style, keeping date display as the grouped day
                                      punchOut = _displayTimeWith27Style(punchOutTime);
                                    } else {
                                      punchOut = DateFormat("dd MMM yyyy hh:mm a")
                                          .format(punchOutTime);
                                    }
                                  }

                                  String punchInAddr = record?["inAddress"] ?? "";
                                  String punchOutAddr = record?["outAddress"] ?? "";

                                  double totalHours = 0;
                                  double otHours = 0;
                                  if (punchInTime != null && punchOutTime != null) {
                                    DateTime adjustedPunchOut = punchOutTime;
                                    if (punchOutTime.isBefore(punchInTime)) {
                                      adjustedPunchOut =
                                          punchOutTime.add(const Duration(days: 1));
                                    }
                                    totalHours = adjustedPunchOut
                                            .difference(punchInTime)
                                            .inMinutes /
                                        60.0;
                                    otHours = totalHours > 12 ? totalHours - 12 : 0;
                                  }

                                  bool isWeekOff =
                                      type == "week_off" || date.weekday == DateTime.sunday;
                                  bool isHoliday = type == "holiday";
                                  bool hasPunch =
                                      punchInTime != null || punchOutTime != null;

                                  Color statusColor;
                                  IconData statusIcon;
                                  String statusText;

                                  if (isHoliday) {
                                    statusColor = Colors.purple;
                                    statusIcon = Icons.celebration;
                                    statusText = ""; // removed "Holiday" display
                                  } else if (isWeekOff && hasPunch) {
                                    statusColor = Colors.blue;
                                    statusIcon = Icons.work;
                                    statusText = "Worked on Week Off";
                                  } else if (isWeekOff) {
                                    statusColor = Colors.grey.shade700;
                                    statusIcon = Icons.beach_access;
                                    statusText = "Week Off";
                                  } else if (!hasPunch) {
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                CircleAvatar(
                                                  radius: isTablet ? 26 : 22,
                                                  backgroundColor:
                                                      statusColor.withOpacity(0.15),
                                                  child: Icon(
                                                    statusIcon,
                                                    color: statusColor,
                                                    size: isTablet ? 26 : 22,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        DateFormat("dd MMM yyyy (EEE)")
                                                            .format(date),
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: isTablet ? 16 : 15,
                                                          color: statusColor,
                                                        ),
                                                      ),
                                                      if (isHoliday && holidayName != null)
                                                        Text(
                                                          "Holiday: $holidayName",
                                                          style: TextStyle(
                                                              fontSize: 13,
                                                              color: statusColor),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                Icon(
                                                  isExpanded
                                                      ? Icons.keyboard_arrow_up
                                                      : Icons.keyboard_arrow_down,
                                                  color: Colors.grey,
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            if (statusText.isNotEmpty)
                                              Text(statusText,
                                                  style: TextStyle(
                                                      color: statusColor,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            if (punchInTime != null)
                                              Text("Punch In: $punchIn"),
                                            if (punchOutTime != null)
                                              Text("Punch Out: $punchOut"),
                                            if (punchInTime != null &&
                                                punchOutTime != null) ...[
                                              Text(
                                                  "Total Hours: ${_formatHoursToHHMM(totalHours)}"),
                                              Text(
                                                  "OT Hours: ${_formatHoursToHHMM(otHours)}"),
                                            ],
                                            if (isExpanded) ...[
                                              if (punchInAddr.isNotEmpty)
                                                Text("Punch In Location: $punchInAddr"),
                                              if (punchOutAddr.isNotEmpty)
                                                Text("Punch Out Location: $punchOutAddr"),
                                            ]
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, int count, Color color, IconData icon,
      bool isTablet,
      {double? hours}) {
    String displayText =
        hours != null ? _formatHoursToHHMM(hours) : count.toString();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: isTablet ? 140 : 115,
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
