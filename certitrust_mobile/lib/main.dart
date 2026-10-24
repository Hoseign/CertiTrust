import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'routes/app_router.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CertiTrustBootstrap());
}

class CertiTrustBootstrap extends StatefulWidget {
  const CertiTrustBootstrap({super.key});

  @override
  State<CertiTrustBootstrap> createState() => _CertiTrustBootstrapState();
}

class _CertiTrustBootstrapState extends State<CertiTrustBootstrap> {
  Object? _startupError;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    setState(() {
      _startupError = null;
      _isReady = false;
    });

    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabasePublishableKey,
      );
      await ApiService.init();
      await ApiService.validateSession();
      await ApiService.updatePresence();
      ApiService.startConnectionMonitoring();
      if (mounted) setState(() => _isReady = true);
    } catch (error, stackTrace) {
      debugPrint('CertiTrust startup failed: $error');
      debugPrint('$stackTrace');
      if (mounted) setState(() => _startupError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isReady) return const CertiTrustApp();

    return MaterialApp(
      title: 'CertiTrust',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF6F8FC),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _startupError == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 20),
                        Text('Preparing CertiTrust...'),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_outlined,
                            size: 42, color: Color(0xFFB42318)),
                        const SizedBox(height: 16),
                        const Text(
                          'CertiTrust could not finish starting.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          _startupError.toString(),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _initializeServices,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

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
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _InstantPageTransitionsBuilder(),
            TargetPlatform.iOS: _InstantPageTransitionsBuilder(),
            TargetPlatform.linux: _InstantPageTransitionsBuilder(),
            TargetPlatform.macOS: _InstantPageTransitionsBuilder(),
            TargetPlatform.windows: _InstantPageTransitionsBuilder(),
            TargetPlatform.fuchsia: _InstantPageTransitionsBuilder(),
          },
        ),
      ),
      routerConfig: AppRouter.router,
    );
  }
}

class _InstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const _InstantPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
