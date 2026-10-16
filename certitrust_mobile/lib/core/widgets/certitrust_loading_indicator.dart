import 'package:flutter/material.dart';

class CertiTrustLoadingIndicator extends StatefulWidget {
  const CertiTrustLoadingIndicator({
    super.key,
    this.size = 72,
    this.message,
  });

  final double size;
  final String? message;

  @override
  State<CertiTrustLoadingIndicator> createState() =>
      _CertiTrustLoadingIndicatorState();
}

class _CertiTrustLoadingIndicatorState extends State<CertiTrustLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _fill;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _fill = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _fill.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget logo() => SizedBox.square(
          dimension: widget.size,
          child: Image.asset(
            'web/assets/images/certitrustlogo.png',
            fit: BoxFit.contain,
          ),
        );

    return Semantics(
      label: widget.message ?? 'Loading',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(opacity: 0.16, child: logo()),
                AnimatedBuilder(
                  animation: _fill,
                  builder: (context, child) => ClipRect(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      heightFactor: 0.12 + _controller.value * 0.88,
                      child: child,
                    ),
                  ),
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        colors.primary,
                        const Color(0xFF1684D8),
                        colors.secondary,
                      ],
                    ).createShader(bounds),
                    child: logo(),
                  ),
                ),
              ],
            ),
          ),
          if (widget.message != null) ...[
            const SizedBox(height: 14),
            Text(
              widget.message!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
