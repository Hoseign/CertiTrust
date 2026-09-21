import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'routes/app_router.dart';
import 'services/api_service.dart';

void main() async {
  // 1. Ensure Flutter bindings are initialized first
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Supabase so the client is ready before the app starts
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
  );

  await ApiService.init();
  await ApiService.validateSession();
  await ApiService.updatePresence();
  ApiService.startConnectionMonitoring();

  runApp(const CertiTrustApp());
}

class CertiTrustApp extends StatelessWidget {
  const CertiTrustApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'CertiTrust',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF003366), // UCU Navy Blue
          primary: const Color(0xFF003366),
          secondary: const Color(0xFFD4AF37), // Gold Accent
        ),
        useMaterial3: true,
      ),
      routerConfig: AppRouter.router,
    );
  }
}
