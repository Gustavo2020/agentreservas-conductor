import 'package:flutter/material.dart';
import '../config/theme.dart';

class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  final String? mensaje;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.mensaje,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.black54,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color: AppTheme.primary,
                  ),
                  if (mensaje != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      mensaje!,
                      style: const TextStyle(color: AppTheme.onBackground),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
