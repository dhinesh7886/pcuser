import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pcuser/mapview.dart';
import 'package:pcuser/razor_pay_service.dart';

class CabBookingPage extends StatefulWidget {
  const CabBookingPage({super.key});

  @override
  State<CabBookingPage> createState() => _CabBookingPageState();
}

class _CabBookingPageState extends State<CabBookingPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();
  final TextEditingController _daysController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  double amount = 100;
  DateTime? _startDate;
  TimeOfDay? _loginTime;
  bool _isLoading = false;
  LatLng? _pickupLatLng;

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _loginTime = picked;
      });
    }
  }

  Future<void> _submitBooking() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _loginTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select date and login time")),
      );
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      final user = FirebaseAuth.instance.currentUser;

      await FirebaseFirestore.instance.collection('bookings').add({
        'userId': user?.uid,
        'pickupPlace': _pickupController.text.trim(),
        'pickupLat': _pickupLatLng?.latitude,
        'pickupLng': _pickupLatLng?.longitude,
        'daysRequired': int.tryParse(_daysController.text.trim()) ?? 1,
        'notes': _notesController.text.trim(),
        'startDate': _startDate!.toIso8601String(),
        'loginTime': _loginTime!.format(context),
        'createdAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Booking submitted successfully!")),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cab Booking"),
        backgroundColor: Colors.deepPurple,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Trip start date
              ListTile(
                leading: const Icon(
                  Icons.calendar_today,
                  color: Colors.deepPurple,
                ),
                title: Text(
                  _startDate == null
                      ? "Select Trip Start Date"
                      : "Trip Start Date: ${_startDate!.day}-${_startDate!.month}-${_startDate!.year}",
                ),
                trailing: ElevatedButton(
                  onPressed: _pickDate,
                  child: const Text("Pick Date"),
                ),
              ),
              const SizedBox(height: 12),

              // Login time
              ListTile(
                leading: const Icon(
                  Icons.access_time,
                  color: Colors.deepPurple,
                ),
                title: Text(
                  _loginTime == null
                      ? "Select Login Time"
                      : "Login Time: ${_loginTime!.format(context)}",
                ),
                trailing: ElevatedButton(
                  onPressed: _pickTime,
                  child: const Text("Pick Time"),
                ),
              ),
              const SizedBox(height: 12),

              // Number of days
              TextFormField(
                controller: _daysController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Number of Days Required",
                  prefixIcon: const Icon(Icons.calendar_view_day),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Enter number of days";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Pickup place
              TextFormField(
                controller: _pickupController,
                decoration: InputDecoration(
                  labelText: "Pickup Place",
                  prefixIcon: const Icon(Icons.location_on),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: _pickupController.text.isEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.map,
                            color: Colors.deepPurple,
                          ),
                          onPressed: () async {
                            final result = await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const MapView(),
                              ),
                            );
                            if (result != null) {
                              setState(() {
                                _pickupLatLng = result["latLng"];
                                _pickupController.text = result["address"];
                              });
                            }
                          },
                        )
                      : IconButton(
                          icon: const Icon(
                            Icons.search,
                            color: Colors.deepPurple,
                          ),
                          onPressed: () async {
                            try {
                              final locations = await locationFromAddress(
                                _pickupController.text.trim(),
                              );
                              if (locations.isNotEmpty) {
                                setState(() {
                                  _pickupLatLng = LatLng(
                                    locations.first.latitude,
                                    locations.first.longitude,
                                  );
                                });
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Could not find location"),
                                ),
                              );
                            }
                          },
                        ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Enter pickup place";
                  }
                  return null;
                },
              ),
              SizedBox(
                height: 15,
              ),
              // Drop place
              TextFormField(
                controller: _dropController,
                decoration: InputDecoration(
                  labelText: "Dropping Place",
                  prefixIcon: const Icon(Icons.location_on),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: _dropController.text.isEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.map,
                            color: Colors.deepPurple,
                          ),
                          onPressed: () async {
                            final result = await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const MapView(),
                              ),
                            );
                            if (result != null) {
                              setState(() {
                                _pickupLatLng = result["latLng"];
                                _dropController.text = result["address"];
                              });
                            }
                          },
                        )
                      : IconButton(
                          icon: const Icon(
                            Icons.search,
                            color: Colors.deepPurple,
                          ),
                          onPressed: () async {
                            try {
                              final locations = await locationFromAddress(
                                _dropController.text.trim(),
                              );
                              if (locations.isNotEmpty) {
                                setState(() {
                                  _pickupLatLng = LatLng(
                                    locations.first.latitude,
                                    locations.first.longitude,
                                  );
                                });
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Could not find location"),
                                ),
                              );
                            }
                          },
                        ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Enter pickup place";
                  }
                  return null;
                },
              ),

              //             TextFormField(
              //               controller: _pickupController,
              //               decoration: InputDecoration(
              //                 labelText: "Pickup Place",
              //                 prefixIcon: const Icon(Icons.location_on),
              //                 border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              //                 suffix: TextButton(onPressed: () async {
              //                 var status = await Permission.location.status;
              //                 if(status.isGranted){
              //                  var r = await Geolocator.getCurrentPosition();
              //                  print(r.latitude);
              //                  print(r.longitude);
              //                 } else {
              //                   await Permission.location.request();
              //                 }
              // // Navigator.of(context).push(MaterialPageRoute(builder: (context) => MapView()));
              //                 }, child: Text("Open Map"))
              //               ),
              //               validator: (value) {
              //                 if (value == null || value.isEmpty) {
              //                   return "Enter pickup place";
              //                 }
              //                 return null;
              //               },
              //             ),
              const SizedBox(height: 12),

              // Additional notes
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: "Additional Notes (Optional)",
                  prefixIcon: const Icon(Icons.note),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      iconColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isLoading ? null : _submitBooking,
                    icon: _isLoading
                        ? const CircularProgressIndicator(
                            color: Colors.white,
                          )
                        : const Icon(Icons.send),
                    label: const Text("Submit"),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.cancel),
                    label: const Text("Cancel"),
                  ),
                ],
              ),
              ElevatedButton(
                  onPressed: () async {
                    RazorpayService().pay(
                        amount: amount,
                        email: "esakkirajam78@gmail.com",
                        contact: "7708072172");
                  },
                  child: Text("Pay"))
            ],
          ),
        ),
      ),
    );
  }
}
