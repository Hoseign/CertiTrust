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
    Widget logo() => SizedBox.square(
          dimension: widget.size,
          child: Image.asset(
            'web/assets/images/certitrustlogo-loading.png',
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.size * 0.2),
              child: ColoredBox(
                color: const Color(0xFF0A192F),
                child: Padding(
                  padding: EdgeInsets.all(widget.size * 0.12),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: 0.65,
                        child: ColorFiltered(
                          colorFilter: const ColorFilter.mode(
                            Color(0xFF60A5FA),
                            BlendMode.srcIn,
                          ),
                          child: logo(),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _fill,
                        builder: (context, child) => ClipRect(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            heightFactor: 0.12 + _fill.value * 0.88,
                            child: child,
                          ),
                        ),
                        child: ColorFiltered(
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                          child: logo(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.message != null) ...[
            const SizedBox(height: 14),
            Text(
              widget.message!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
