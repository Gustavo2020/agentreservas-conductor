import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../widgets/foto_geolocalizada.dart';
import '../widgets/loading_overlay.dart';

class ChecklistScreen extends StatefulWidget {
  final int solicitudId;
  const ChecklistScreen({super.key, required this.solicitudId});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  int? _checklistId;
  bool _loading = true;
  bool _enviando = false;
  bool _yaEnviado = false;  // true si ya fue enviado y espera aprobación
  bool _aprobado  = false;
  bool _rechazado = false;
  String? _error;

  // Estado local de cada foto
  final Map<String, String?> _fotos = {
    'foto_llantas': null,
    'foto_equipo_carreteras': null,
    'foto_aceite': null,
    'foto_liquido_frenos': null,
    'foto_refrigerante': null,
  };
  final Map<String, double?> _lats = {};
  final Map<String, double?> _lngs = {};

  static const _etiquetas = {
    'foto_llantas': '🔵 Llantas',
    'foto_equipo_carreteras': '🔵 Equipo de carreteras',
    'foto_aceite': '🔵 Nivel de aceite',
    'foto_liquido_frenos': '🔵 Líquido de frenos',
    'foto_refrigerante': '🔵 Refrigerante',
  };

  @override
  void initState() {
    super.initState();
    _iniciarChecklist();
  }

  Future<void> _iniciarChecklist() async {
    try {
      final api = context.read<ApiService>();
      final data = await api.iniciarChecklist(widget.solicitudId);
      _checklistId = data['checklist_id'] as int?;

      // Cargar estado actual del checklist para saber si ya fue enviado
      final ckData = await api.get(
          '/api/conductor/viajes/${widget.solicitudId}/checklist');
      final ck = ckData['checklist'];
      if (ck != null && ck is Map<String, dynamic>) {
        final enviado = ck['enviado_revision'] == true || ck['enviado_revision'] == 1;
        final estado  = ck['estado'] as String? ?? 'PENDIENTE';

        // Restaurar fotos ya subidas — protege contra muerte de proceso Android
        // mientras la cámara estaba abierta (proceso kill + recreación de actividad).
        const latKeys = {
          'foto_llantas':          'lat_llantas',
          'foto_equipo_carreteras':'lat_equipo_carreteras',
          'foto_aceite':           'lat_aceite',
          'foto_liquido_frenos':   'lat_liquido_frenos',
          'foto_refrigerante':     'lat_refrigerante',
        };
        const lngKeys = {
          'foto_llantas':          'lng_llantas',
          'foto_equipo_carreteras':'lng_equipo_carreteras',
          'foto_aceite':           'lng_aceite',
          'foto_liquido_frenos':   'lng_liquido_frenos',
          'foto_refrigerante':     'lng_refrigerante',
        };
        for (final campo in _fotos.keys.toList()) {
          final path = ck[campo] as String?;
          if (path != null && path.isNotEmpty) {
            _fotos[campo] = path;
            _lats[campo] = (ck[latKeys[campo]] as num?)?.toDouble();
            _lngs[campo] = (ck[lngKeys[campo]] as num?)?.toDouble();
          }
        }

        setState(() {
          _yaEnviado = enviado && estado == 'PENDIENTE';
          _aprobado  = estado == 'APROBADO';
          _rechazado = estado == 'RECHAZADO';
          _loading   = false;
        });
        return;
      }
      setState(() => _loading = false);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _onFotoCapturada(
    String campoFoto,
    FotoGeoResult result,
    String? comentario,
  ) async {
    if (_checklistId == null) return;
    try {
      final api = context.read<ApiService>();
      await api.postMultipart(
        '/api/conductor/viajes/${widget.solicitudId}/checklist/foto'
        '?campo_foto=$campoFoto'
        '&lat=${result.lat}&lng=${result.lng}'
        '&comentario=${Uri.encodeComponent(comentario ?? '')}',
        fields: {},
        fileField: 'archivo',
        fileBytes: result.bytes,
        filename: result.filename,
        contentType: 'image/jpeg',
      );
      setState(() {
        _fotos[campoFoto] = result.filename;
        _lats[campoFoto] = result.lat;
        _lngs[campoFoto] = result.lng;
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.message}'),
              backgroundColor: AppTheme.error),
        );
      }
    }
  }

  bool get _todasLasFotos =>
      _fotos.values.every((v) => v != null && v.isNotEmpty);

  Future<void> _enviarChecklist() async {
    setState(() => _enviando = true);
    try {
      final api = context.read<ApiService>();
      await api.enviarChecklist(widget.solicitudId);
      setState(() {
        _yaEnviado = true;
        _enviando  = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _enviando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checklist Preoperacional')),
      body: LoadingOverlay(
        isLoading: _loading,
        child: _loading
            ? const SizedBox.shrink()
            : _error != null
                ? Center(
                    child: Text(_error!,
                        style: const TextStyle(color: AppTheme.error)),
                  )
                : _aprobado
                    ? _buildEstado(
                        icon: Icons.verified,
                        color: AppTheme.success,
                        titulo: 'Checklist aprobado',
                        subtitulo: 'El responsable aprobó el checklist. Puedes iniciar el viaje.',
                      )
                    : _rechazado
                        ? _buildEstado(
                            icon: Icons.cancel,
                            color: AppTheme.error,
                            titulo: 'Checklist rechazado',
                            subtitulo: 'El responsable rechazó el checklist. Toma nuevas fotos y vuelve a enviar.',
                            mostrarVolver: true,
                          )
                        : _yaEnviado
                            ? _buildEstado(
                                icon: Icons.hourglass_top,
                                color: AppTheme.warning,
                                titulo: 'Esperando aprobación',
                                subtitulo: 'El checklist fue enviado al responsable de la empresa. Recibirás una notificación cuando sea revisado.',
                              )
                            : _buildForm(),
      ),
    );
  }

  Widget _buildEstado({
    required IconData icon,
    required Color color,
    required String titulo,
    required String subtitulo,
    bool mostrarVolver = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 72),
            const SizedBox(height: 16),
            Text(titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(subtitulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.onSurface, fontSize: 14)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Volver'),
            ),
            if (mostrarVolver) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() {
                  _rechazado = false;
                  _yaEnviado = false;
                }),
                child: const Text('Editar checklist'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final campos = _fotos.keys.toList();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: campos.length + 1,
      itemBuilder: (_, index) {
        if (index < campos.length) {
          final campo = campos[index];
          final tieneFoto =
              _fotos[campo] != null && _fotos[campo]!.isNotEmpty;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        tieneFoto ? Icons.check_circle : Icons.circle_outlined,
                        color: tieneFoto
                            ? AppTheme.success
                            : AppTheme.onSurface,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _etiquetas[campo] ?? campo,
                        style: const TextStyle(
                          color: AppTheme.onBackground,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FotoGeolocalizadaWidget(
                    etiqueta: _etiquetas[campo] ?? campo,
                    campoFoto: campo,
                    fotoPath: _fotos[campo],
                    lat: _lats[campo],
                    lng: _lngs[campo],
                    onFotoCapturada: (result, comentario) =>
                        _onFotoCapturada(campo, result, comentario),
                  ),
                ],
              ),
            ),
          );
        }
        // Footer: send button or missing-photos hint
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _todasLasFotos
              ? SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _enviando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.onPrimary),
                          )
                        : const Icon(Icons.send),
                    label: const Text('Enviar a revisión'),
                    onPressed: _enviando ? null : _enviarChecklist,
                  ),
                )
              : Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Faltan ${_fotos.values.where((v) => v == null).length} foto(s) por cargar',
                    style: const TextStyle(color: AppTheme.warning, fontSize: 13),
                  ),
                ),
        );
      },
    );
  }
}
