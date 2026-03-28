import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/soporte.dart';
import '../models/trayecto.dart';
import '../providers/viaje_provider.dart';
import '../services/api_service.dart';
import '../services/log_service.dart';
import '../widgets/estado_badge.dart';

final _fmt = NumberFormat('#,###', 'es_CO');

class SoportesScreen extends StatefulWidget {
  final int solicitudId;
  final int diaNumero;
  const SoportesScreen({
    super.key,
    required this.solicitudId,
    required this.diaNumero,
  });

  @override
  State<SoportesScreen> createState() => _SoportesScreenState();
}

class _SoportesScreenState extends State<SoportesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<ViajeProvider>()
          .cargarSoportesDia(widget.solicitudId, widget.diaNumero);
    });
  }

  void _abrirFormulario() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SoporteForm(
        solicitudId: widget.solicitudId,
        diaNumero: widget.diaNumero,
        onGuardado: () => context
            .read<ViajeProvider>()
            .cargarSoportesDia(widget.solicitudId, widget.diaNumero),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ViajeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Soportes — Día ${widget.diaNumero}'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primary,
        onPressed: _abrirFormulario,
        child: const Icon(Icons.add, color: AppTheme.onPrimary),
      ),
      body: Column(
        children: [
          Expanded(
            child: prov.loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary))
                : prov.soportesDia.isEmpty
                    ? const Center(
                        child: Text('Sin soportes registrados',
                            style: TextStyle(color: AppTheme.onSurface)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: prov.soportesDia.length,
                        itemBuilder: (_, i) {
                          final s = prov.soportesDia[i];
                          return _SoporteCard(soporte: s);
                        },
                      ),
          ),
          // Total del día
          Container(
            color: AppTheme.surface,
            padding: const EdgeInsets.fromLTRB(16, 12, 80, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total día',
                    style: TextStyle(
                        color: AppTheme.onBackground,
                        fontWeight: FontWeight.w600)),
                Text(
                  '\$${_fmt.format(prov.totalDia)}',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SoporteCard extends StatelessWidget {
  final Soporte soporte;
  const _SoporteCard({required this.soporte});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    soporte.tipo,
                    style: const TextStyle(
                        color: AppTheme.onBackground,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${_fmt.format(soporte.monto)}',
                    style:
                        const TextStyle(color: AppTheme.primary, fontSize: 16),
                  ),
                ],
              ),
            ),
            EstadoBadge(estado: soporte.estado),
          ],
        ),
      ),
    );
  }
}

// ── Formulario nuevo soporte ──────────────────────────────────────────────────

class _SoporteForm extends StatefulWidget {
  final int solicitudId;
  final int diaNumero;
  final VoidCallback onGuardado;
  const _SoporteForm({
    required this.solicitudId,
    required this.diaNumero,
    required this.onGuardado,
  });

  @override
  State<_SoporteForm> createState() => _SoporteFormState();
}

class _SoporteFormState extends State<_SoporteForm> {
  String _tipo = 'PEAJE';
  final _montoCtrl = TextEditingController();
  Uint8List? _fotoBytes;
  String? _fotoNombre;
  bool _capturando = false;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _tomarFoto() async {
    if (_capturando) return;
    setState(() {
      _capturando = true;
      _error = null;
    });
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (xFile == null || !mounted) return;
      final bytes = await xFile.readAsBytes();
      if (!mounted) return;
      setState(() {
        _fotoBytes = bytes;
        _fotoNombre = 'soporte_${DateTime.now().millisecondsSinceEpoch}.jpg';
      });
    } on Exception catch (e, st) {
      AppLogger.error('SoportesScreen: error al capturar foto', e,
          stackTrace: st);
      if (mounted) {
        setState(
            () => _error = 'No se pudo abrir la cámara. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _capturando = false);
    }
  }

  Future<void> _guardar() async {
    final monto = double.tryParse(_montoCtrl.text.replaceAll(',', '.'));
    if (monto == null || monto <= 0) {
      setState(() => _error = 'Ingresa un monto válido mayor a 0');
      return;
    }
    if (_fotoBytes == null) {
      setState(() => _error = 'Toma una foto del soporte');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      // Resolver el trayecto del día actual desde el viaje en curso.
      final viaje = context.read<ViajeProvider>().viajeActual;
      final trayectos = viaje?.trayectos ?? const <Trayecto>[];
      Trayecto? trayecto;
      for (final t in trayectos) {
        if (t.diaNumero == widget.diaNumero) {
          trayecto = t;
          break;
        }
      }
      trayecto ??= trayectos.isNotEmpty ? trayectos.first : null;
      final trayectoId = trayecto?.id ?? 1;

      final api = context.read<ApiService>();
      await api.subirSoporte(
        widget.solicitudId,
        tipo: _tipo,
        monto: monto,
        diaNumero: widget.diaNumero,
        trayectoId: trayectoId,
        fileBytes: _fotoBytes!,
        filename: _fotoNombre!,
        contentType: 'image/jpeg',
      );

      widget.onGuardado();
      if (!mounted) return;

      // ¿Agregar otro?
      final otro = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Soporte guardado'),
          content: const Text('¿Deseas agregar otro soporte?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No')),
            ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sí')),
          ],
        ),
      );

      if (otro == true) {
        setState(() {
          _montoCtrl.clear();
          _fotoBytes = null;
          _fotoNombre = null;
          _guardando = false;
          _error = null;
        });
      } else {
        if (mounted) Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      AppLogger.error('SoportesScreen: error al guardar soporte', e, context: {
        'solicitud_id': '${widget.solicitudId}',
        'dia': '${widget.diaNumero}'
      });
      if (mounted) {
        setState(() {
          _error = e.message;
          _guardando = false;
        });
      }
    } on Exception catch (e, st) {
      AppLogger.error('SoportesScreen: error de red al guardar soporte', e,
          stackTrace: st,
          context: {
            'solicitud_id': '${widget.solicitudId}',
            'dia': '${widget.diaNumero}'
          });
      if (mounted) {
        setState(() {
          _error = 'Error de red. Verifica tu conexión e intenta de nuevo.';
          _guardando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Nuevo soporte',
            style: TextStyle(
                color: AppTheme.onBackground,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Tipo
          Wrap(
            spacing: 8,
            children: ['PEAJE', 'PARQUEADERO', 'LAVADO'].map((t) {
              return ChoiceChip(
                label: Text(t),
                selected: _tipo == t,
                onSelected: (_) => setState(() => _tipo = t),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Monto
          TextField(
            controller: _montoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Monto',
              prefixText: '\$ ',
            ),
          ),
          const SizedBox(height: 12),

          // Foto
          OutlinedButton.icon(
            icon: _capturando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt),
            label: Text(
              _capturando
                  ? 'Iniciando cámara...'
                  : _fotoBytes == null
                      ? '📷 Tomar foto del soporte'
                      : '✓ Foto capturada (cambiar)',
            ),
            style: _fotoBytes != null && !_capturando
                ? OutlinedButton.styleFrom(foregroundColor: AppTheme.success)
                : null,
            onPressed: _capturando ? null : _tomarFoto,
          ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppTheme.error)),
          ],

          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.onPrimary),
                  )
                : const Text('Guardar soporte'),
          ),
        ],
      ),
    );
  }
}
