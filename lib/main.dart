import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:pcuser/home.dart';
import 'package:pcuser/login_page.dart';
import 'package:pcuser/splash_screen.dart';
import 'package:pcuser/user_provider.dart';
import 'package:provider/provider.dart';


void main() async {
 await WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase initialization error: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => UserProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Flutter Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: SplashScreen(),
        routes: {
          '/home': (_) => const UsersHomePage(),
        },
      ),
    );
  }
}
