import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'services/local_store.dart';
import 'services/notification_service.dart';
import 'theme.dart';

/// Health Assistant APK — stage 1 skeleton.
/// Firebase (project "Health Assistant", health-assistant-65709, Spark plan)
/// + Google sign-in + offline-first Firestore sync + 12-tab shell.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // Firestore offline persistence: reads/writes work offline, sync when
  // the phone is back online (SyncService handles the push/pull).
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  // Google Sign-In v7: initialize once (Android reads the OAuth client
  // from google-services.json).
  await GoogleSignIn.instance.initialize();
  // System notifications (reminders that fire when the app is closed).
  // Guarded: notification init/scheduling must never block startup.
  try {
    await NotificationService().init();
    await LocalStore().load();
    await NotificationService().scheduleAll();
  } catch (_) {}
  runApp(const HealthAssistantApp());
}

class HealthAssistantApp extends StatelessWidget {
  const HealthAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '🩺 ကျန်းမာရေး',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData) {
            return const HomeShell();
          }
          return const AuthScreen();
        },
      ),
    );
  }
}
