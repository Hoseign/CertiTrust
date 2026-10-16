import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/certitrust_loading_indicator.dart';
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
      if (!ApiService.isAuthenticated) {
        context.go('/');
        return;
      }
      final contactId = ApiService.frozenByContact?['id']?.toString();
      final frozenChat = contactId == null
          ? '/frozen-chat'
          : '/frozen-chat?with_user_id=${Uri.encodeQueryComponent(contactId)}';
      context.go(ApiService.isAccessFrozen ? frozenChat : '/dashboard');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: const CertiTrustLoadingIndicator(
            size: 132,
            message: 'Preparing your credentials...',
          ),
        ),
      ),
    );
  }
}
