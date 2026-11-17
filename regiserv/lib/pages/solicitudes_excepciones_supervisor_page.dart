import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'detalle_solicitud_excepcion_page.dart';

class SolicitudesExcepcionesSupervisorPage extends StatefulWidget {
  const SolicitudesExcepcionesSupervisorPage({super.key});

  @override
  State<SolicitudesExcepcionesSupervisorPage> createState() =>
      _SolicitudesExcepcionesSupervisorPageState();
}

class _SolicitudesExcepcionesSupervisorPageState
    extends State<SolicitudesExcepcionesSupervisorPage> {
  SupabaseClient get supabase => Supabase.instance.client;

  final List<Map<String, dynamic>> solicitudes = <Map<String, dynamic>>[];

  bool cargando = true;
  String? mensajeError;

  @override
  void initState() {
    super.initState();
    cargarSolicitudes();
  }

  // =============================================================
  // CARGAR SOLICITUDES REALES
  // =============================================================

  Future<void> cargarSolicitudes() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;
      });
    }

    try {
      final dynamic respuesta = await supabase.rpc(
        'listar_solicitudes_cierre_excepcional',
      );

      final List<dynamic> filas = respuesta is List ? respuesta : <dynamic>[];

      final List<Map<String, dynamic>> temporales = <Map<String, dynamic>>[];

      for (final dynamic fila in filas) {
        if (fila is! Map) {
          continue;
        }

        final Map<String, dynamic> datos = Map<String, dynamic>.from(fila);

        final DateTime? fechaSolicitud = _convertirFecha(
          datos['fecha_solicitud'],
        );

        final DateTime? inicio = _convertirFecha(datos['fecha_hora_inicio']);

        final String codigo = _texto(
          datos['espacio_codigo'],
          defecto: 'Sin código',
        );

        final String nombre = _texto(datos['espacio_nombre'], defecto: codigo);

        temporales.add(<String, dynamic>{
          'idAlerta': datos['id_alerta'],
          'idRegistroAseo': datos['id_registro_aseo'],
          'fecha': _formatearFecha(fechaSolicitud),
          'horaSolicitud': _formatearHora(fechaSolicitud),
          'lugar': nombre,
          'codigoEspacio': codigo,
          'tipo': _texto(datos['tipo_espacio'], defecto: 'Sin tipo'),
          'responsable': _texto(
            datos['responsable'],
            defecto: 'Sin responsable',
          ),
          'inicio': _formatearHora(inicio),
          'motivo': _texto(datos['motivo'], defecto: 'Cierre excepcional'),
          'detalle': _texto(datos['detalle'], defecto: 'Sin detalle adicional'),
          'estado': _texto(datos['estado_solicitud'], defecto: 'Pendiente'),
        });
      }

      if (!mounted) {
        return;
      }

      setState(() {
        solicitudes
          ..clear()
          ..addAll(temporales);

        cargando = false;
      });
    } catch (error, stackTrace) {
      debugPrint('ERROR CARGANDO SOLICITUDES: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;
        mensajeError = 'No fue posible cargar las solicitudes desde Supabase.';
      });
    }
  }

  // =============================================================
  // UTILIDADES
  // =============================================================

  String _texto(dynamic valor, {required String defecto}) {
    if (valor == null) {
      return defecto;
    }

    final String texto = valor.toString().trim();

    return texto.isEmpty ? defecto : texto;
  }

  DateTime? _convertirFecha(dynamic valor) {
    if (valor == null) {
      return null;
    }

    try {
      return DateTime.parse(valor.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _formatearFecha(DateTime? fecha) {
    if (fecha == null) {
      return '-';
    }

    final String dia = fecha.day.toString().padLeft(2, '0');
    final String mes = fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  String _formatearHora(DateTime? fecha) {
    if (fecha == null) {
      return '-';
    }

    final String hora = fecha.hour.toString().padLeft(2, '0');
    final String minuto = fecha.minute.toString().padLeft(2, '0');

    return '$hora:$minuto';
  }

  // =============================================================
  // ABRIR DETALLE
  // =============================================================

  Future<void> abrirSolicitud(Map<String, dynamic> solicitud) async {
    final int? idAlerta = int.tryParse(solicitud['idAlerta'].toString());

    final int? idRegistro = int.tryParse(
      solicitud['idRegistroAseo'].toString(),
    );

    if (idAlerta == null || idRegistro == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible identificar la solicitud.'),
        ),
      );

      return;
    }

    final bool? resuelta = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => DetalleSolicitudExcepcionPage(
          idAlerta: idAlerta,
          idRegistroAseo: idRegistro,
          fecha: solicitud['fecha'].toString(),
          horaSolicitud: solicitud['horaSolicitud'].toString(),
          lugar: solicitud['lugar'].toString(),
          responsable: solicitud['responsable'].toString(),
          inicio: solicitud['inicio'].toString(),
          motivo: solicitud['motivo'].toString(),
          detalle: solicitud['detalle'].toString(),
          estadoInicial: solicitud['estado'].toString(),
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    // Tanto una aprobación como un rechazo resuelven la solicitud.
    if (resuelta == true) {
      await cargarSolicitudes();
    }
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Solicitudes y excepciones',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: cargando ? null : cargarSolicitudes,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Solicitudes pendientes',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Aquí aparecen las labores en las que un Auxiliar solicitó intervención del Supervisor.',
                        style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
                      ),
                      const SizedBox(height: 18),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.support_agent,
                              color: Color(0xFFD97706),
                              size: 30,
                            ),
                            const SizedBox(width: 14),
                            Text(
                              '${solicitudes.length} '
                              '${solicitudes.length == 1 ? 'solicitud pendiente' : 'solicitudes pendientes'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: cargando
                      ? const Center(child: CircularProgressIndicator())
                      : mensajeError != null
                      ? _ErrorSolicitudes(
                          mensaje: mensajeError!,
                          onReintentar: cargarSolicitudes,
                        )
                      : solicitudes.isEmpty
                      ? const _SinSolicitudes()
                      : RefreshIndicator(
                          onRefresh: cargarSolicitudes,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                            itemCount: solicitudes.length,
                            itemBuilder: (context, index) {
                              final Map<String, dynamic> solicitud =
                                  solicitudes[index];

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _TarjetaSolicitud(
                                  solicitud: solicitud,
                                  onTap: () {
                                    abrirSolicitud(solicitud);
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =================================================================
// TARJETA
// =================================================================

class _TarjetaSolicitud extends StatelessWidget {
  final Map<String, dynamic> solicitud;
  final VoidCallback onTap;

  const _TarjetaSolicitud({required this.solicitud, required this.onTap});

  Color get colorEstado {
    switch (solicitud['estado']) {
      case 'Leída':
      case 'En atención':
        return const Color(0xFF2563EB);

      default:
        return const Color(0xFFD97706);
    }
  }

  Color get fondoEstado {
    switch (solicitud['estado']) {
      case 'Leída':
      case 'En atención':
        return const Color(0xFFEFF6FF);

      default:
        return const Color(0xFFFFFBEB);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${solicitud['fecha']} · ${solicitud['horaSolicitud']}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: fondoEstado,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      solicitud['estado'].toString(),
                      style: TextStyle(
                        color: colorEstado,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: Color(0xFF1565C0),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      solicitud['lugar'].toString(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
                ],
              ),

              const SizedBox(height: 5),

              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(
                  solicitud['tipo'].toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 20,
                    color: Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      solicitud['responsable'].toString(),
                      style: const TextStyle(color: Color(0xFF4B5563)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.report_problem_outlined,
                      color: Color(0xFFD97706),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        solicitud['motivo'].toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =================================================================
// ERROR
// =================================================================

class _ErrorSolicitudes extends StatelessWidget {
  final String mensaje;
  final Future<void> Function() onReintentar;

  const _ErrorSolicitudes({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 54,
              color: Color(0xFF9CA3AF),
            ),
            const SizedBox(height: 14),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF4B5563)),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () {
                onReintentar();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

// =================================================================
// SIN SOLICITUDES
// =================================================================

class _SinSolicitudes extends StatelessWidget {
  const _SinSolicitudes();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 56,
              color: Color(0xFF16A34A),
            ),
            SizedBox(height: 14),
            Text(
              'No hay solicitudes pendientes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 6),
            Text(
              'No existen solicitudes de cierre excepcional por revisar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
