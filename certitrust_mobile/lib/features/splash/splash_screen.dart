import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      context.go(ApiService.isAuthenticated ? '/dashboard' : '/');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('web/assets/images/certitrustlogo.png',
                  height: 120, fit: BoxFit.contain),
              const SizedBox(height: 18),
              Text('CertiTrust',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 22),
              SizedBox(
                  width: 150, child: LinearProgressIndicator(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
