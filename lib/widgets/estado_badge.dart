import 'package:flutter/material.dart';
import '../config/theme.dart';

class EstadoBadge extends StatelessWidget {
  final String estado;
  final bool pulsante;

  const EstadoBadge({super.key, required this.estado, this.pulsante = false});

  @override
  Widget build(BuildContext context) {
    final (color, label) = _info(estado);
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );

    if (pulsante) {
      return _PulsatingBadge(child: badge, color: color);
    }
    return badge;
  }

  static (Color, String) _info(String estado) => switch (estado) {
        'APROBADO'   => (AppTheme.success, 'Próximo'),
        'EN_CURSO'   => (AppTheme.warning, 'En curso'),
        'FINALIZADO' => (AppTheme.onSurface, 'Finalizado'),
        'CANCELADO'  => (AppTheme.error, 'Cancelado'),
        'PENDIENTE'  => (AppTheme.warning, 'Pendiente'),
        'RECHAZADO'  => (AppTheme.error, 'Rechazado'),
        _            => (AppTheme.onSurface, estado),
      };
}

class _PulsatingBadge extends StatefulWidget {
  final Widget child;
  final Color color;
  const _PulsatingBadge({required this.child, required this.color});

  @override
  State<_PulsatingBadge> createState() => _PulsatingBadgeState();
}

class _PulsatingBadgeState extends State<_PulsatingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _anim, child: widget.child);
  }
}
