import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/sesion_data.dart';
import '../core/push/notificaciones_push_service.dart';
import 'perfil_mantencion_page.dart';
import 'incidencias_mantencion_page.dart';
import 'detalle_incidencia_mantencion_page.dart';
import 'notificaciones_page.dart';

class MantencionHomePage extends StatefulWidget {
  const MantencionHomePage({super.key});

  @override
  State<MantencionHomePage> createState() => _MantencionHomePageState();
}

class _MantencionHomePageState extends State<MantencionHomePage> {
  final SupabaseClient supabase = Supabase.instance.client;

  final List<Map<String, dynamic>> incidencias = <Map<String, dynamic>>[];

  int reportadasHoy = 0;
  int enAtencionHoy = 0;
  int resueltasHoy = 0;

  bool cargando = true;
  String? mensajeError;

  @override
  void initState() {
    super.initState();
    cargarIncidencias();
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

  bool _esHoy(DateTime? fecha) {
    if (fecha == null) {
      return false;
    }

    final DateTime ahora = DateTime.now();

    return fecha.year == ahora.year &&
        fecha.month == ahora.month &&
        fecha.day == ahora.day;
  }

  String _formatearFechaHora(DateTime? fecha) {
    if (fecha == null) {
      return 'Sin fecha';
    }

    final String dia = fecha.day.toString().padLeft(2, '0');

    final String mes = fecha.month.toString().padLeft(2, '0');

    final String hora = fecha.hour.toString().padLeft(2, '0');

    final String minuto = fecha.minute.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year} '
        '$hora:$minuto';
  }

  String _ubicacion(Map<String, dynamic> datos) {
    final String edificio = _texto(datos['edificio'], defecto: 'Sin edificio');

    final String piso = datos['numero_nivel'] == null
        ? 'Sin piso'
        : 'Piso ${datos['numero_nivel']}';

    final String espacio = _texto(
      datos['espacio_nombre'],
      defecto: _texto(datos['espacio_codigo'], defecto: 'Sin espacio'),
    );

    return '$edificio · $piso · $espacio';
  }

  // =============================================================
  // CARGAR INCIDENCIAS REALES
  // =============================================================

  Future<void> cargarIncidencias() async {
    if (!mounted) {
      return;
    }

    setState(() {
      cargando = true;
      mensajeError = null;
    });

    try {
      final dynamic respuesta = await supabase.rpc(
        'listar_incidencias_mantencion',
      );

      final List<dynamic> filas = respuesta is List ? respuesta : <dynamic>[];

      final List<Map<String, dynamic>> nuevasIncidencias =
          <Map<String, dynamic>>[];

      int nuevasReportadasHoy = 0;
      int nuevasEnAtencionHoy = 0;
      int nuevasResueltasHoy = 0;

      for (final dynamic fila in filas) {
        if (fila is! Map) {
          continue;
        }

        final Map<String, dynamic> datos = Map<String, dynamic>.from(fila);

        nuevasIncidencias.add(datos);

        final DateTime? fechaAlerta = _convertirFecha(datos['fecha_alerta']);

        final DateTime? fechaInicioAtencion = _convertirFecha(
          datos['fecha_inicio_atencion'],
        );

        final DateTime? fechaResolucion = _convertirFecha(
          datos['fecha_resolucion'],
        );

        if (_esHoy(fechaAlerta)) {
          nuevasReportadasHoy++;
        }

        if (_esHoy(fechaInicioAtencion)) {
          nuevasEnAtencionHoy++;
        }

        if (_esHoy(fechaResolucion)) {
          nuevasResueltasHoy++;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        incidencias
          ..clear()
          ..addAll(nuevasIncidencias);

        reportadasHoy = nuevasReportadasHoy;

        enAtencionHoy = nuevasEnAtencionHoy;

        resueltasHoy = nuevasResueltasHoy;

        cargando = false;
        mensajeError = null;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'ERROR cargarIncidencias Mantención: '
        '$error',
      );
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        incidencias.clear();

        reportadasHoy = 0;
        enAtencionHoy = 0;
        resueltasHoy = 0;

        cargando = false;

        mensajeError = 'No fue posible cargar las incidencias de Mantención.';
      });
    }
  }

  // =============================================================
  // INCIDENCIAS
  // =============================================================

  Future<void> abrirIncidencias() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const IncidenciasMantencionPage(),
      ),
    );

    if (!mounted) {
      return;
    }

    await cargarIncidencias();
  }

  Future<void> abrirDetalleIncidencia(Map<String, dynamic> incidencia) async {
    final int? idAlerta = int.tryParse(
      incidencia['id_alerta']?.toString() ?? '',
    );

    if (idAlerta == null) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            DetalleIncidenciaMantencionPage(idAlerta: idAlerta),
      ),
    );

    if (!mounted) {
      return;
    }

    await cargarIncidencias();
  }

  // =============================================================
  // CERRAR SESIÓN
  // =============================================================

  Future<void> cerrarSesion() async {
    // Retira la asociación push con el JWT vigente antes de salir.
    await NotificacionesPushService.instance.retirarAntesCerrarSesion();

    try {
      await supabase.auth.signOut();
    } catch (error) {
      debugPrint(
        'ERROR cerrarSesion Mantención: '
        '$error',
      );
    }

    SesionData.cerrarSesion();

    if (!mounted) {
      return;
    }

    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final String nombre = SesionData.nombreActual.trim().isNotEmpty
        ? SesionData.nombreActual
        : 'Mantención';

    final String primerNombre = SesionData.primerNombreActual.trim().isNotEmpty
        ? SesionData.primerNombreActual
        : 'Mantención';

    final String inicial = SesionData.inicialActual.trim().isNotEmpty
        ? SesionData.inicialActual
        : 'M';

    final List<Map<String, dynamic>> recientes = incidencias.take(5).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,

        title: const Text(
          'RegiServ',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),

        actions: [
          const CampanaNotificaciones(),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: cargando ? null : cargarIncidencias,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      drawer: Drawer(
        backgroundColor: Colors.white,

        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                color: const Color(0xFFEFF6FF),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: const Color(0xFF1565C0),
                      child: Text(
                        inicial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Text(
                      nombre,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 4),

                    const Text(
                      'Personal de Mantención',
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              ListTile(
                leading: const Icon(Icons.construction_outlined),
                title: const Text('Incidencias'),
                onTap: () {
                  Navigator.pop(context);
                  abrirIncidencias();
                },
              ),

              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Mi perfil'),
                onTap: () {
                  Navigator.pop(context);

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PerfilMantencionPage(),
                    ),
                  );
                },
              ),

              const Spacer(),

              const Divider(),

              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text(
                  'Cerrar sesión',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  Navigator.pop(context);
                  cerrarSesion();
                },
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),

      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: cargarIncidencias,

          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),

            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),

            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 700),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      'Hola, $primerNombre',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 4),

                    const Text(
                      'Gestión de incidencias de infraestructura',
                      style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
                    ),

                    const SizedBox(height: 28),

                    // =============================================
                    // RESUMEN
                    // =============================================
                    Container(
                      width: double.infinity,

                      padding: const EdgeInsets.all(20),

                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Resumen de hoy',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                              ),

                              if (cargando)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          Row(
                            children: [
                              Expanded(
                                child: _IndicadorMantencion(
                                  icono: Icons.pending_actions_outlined,
                                  valor: cargando ? '...' : '$reportadasHoy',
                                  titulo: 'Reportadas hoy',
                                  color: const Color(0xFFD97706),
                                ),
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: _IndicadorMantencion(
                                  icono: Icons.engineering_outlined,
                                  valor: cargando ? '...' : '$enAtencionHoy',
                                  titulo: 'En atención hoy',
                                  color: const Color(0xFF2563EB),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          _IndicadorMantencion(
                            icono: Icons.task_alt_outlined,
                            valor: cargando ? '...' : '$resueltasHoy',
                            titulo: 'Resueltas hoy',
                            color: const Color(0xFF16A34A),
                          ),

                          if (mensajeError != null) ...[
                            const SizedBox(height: 14),

                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),

                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF7ED),
                                borderRadius: BorderRadius.circular(10),
                              ),

                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: Color(0xFFC2410C),
                                  ),

                                  const SizedBox(width: 8),

                                  Expanded(
                                    child: Text(
                                      mensajeError!,
                                      style: const TextStyle(
                                        color: Color(0xFF9A3412),
                                      ),
                                    ),
                                  ),

                                  IconButton(
                                    onPressed: cargarIncidencias,
                                    icon: const Icon(Icons.refresh),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // =============================================
                    // INCIDENCIAS RECIENTES
                    // =============================================
                    const Text(
                      'Incidencias recientes',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Daños de infraestructura informados desde las labores de aseo.',
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),

                    const SizedBox(height: 16),

                    if (!cargando && mensajeError == null && recientes.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),

                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),

                        child: const Column(
                          children: [
                            Icon(
                              Icons.verified_outlined,
                              size: 44,
                              color: Color(0xFF16A34A),
                            ),

                            SizedBox(height: 10),

                            Text(
                              'No hay incidencias registradas',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F2937),
                              ),
                            ),

                            SizedBox(height: 5),

                            Text(
                              'Cuando se reporte un daño de infraestructura aparecerá aquí.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      ),

                    if (!cargando && recientes.isNotEmpty)
                      ...recientes.map(
                        (incidencia) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),

                          child: _IncidenciaReciente(
                            onTap: () {
                              abrirDetalleIncidencia(incidencia);
                            },
                            categoria: _texto(
                              incidencia['categoria_observacion'],
                              defecto: 'Daño a infraestructura',
                            ),
                            detalle: _texto(
                              incidencia['detalle_observacion'],
                              defecto: 'Sin detalle',
                            ),
                            ubicacion: _ubicacion(incidencia),
                            fecha: _formatearFechaHora(
                              _convertirFecha(incidencia['fecha_alerta']),
                            ),
                            estado: _texto(
                              incidencia['estado_alerta'],
                              defecto: 'Pendiente',
                            ),
                            tecnico: _texto(
                              incidencia['tecnico_asignado'],
                              defecto: '',
                            ),
                          ),
                        ),
                      ),

                    if (!cargando && incidencias.length > recientes.length) ...[
                      const SizedBox(height: 4),

                      Text(
                        'Mostrando ${recientes.length} de '
                        '${incidencias.length} incidencias.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------
// INDICADOR
// -----------------------------------------------------------------

class _IndicadorMantencion extends StatelessWidget {
  final IconData icono;
  final String valor;
  final String titulo;
  final Color color;

  const _IndicadorMantencion({
    required this.icono,
    required this.valor,
    required this.titulo,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Icon(icono, color: color, size: 26),

          const SizedBox(height: 10),

          Text(
            valor,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),

          const SizedBox(height: 3),

          Text(
            titulo,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------
// INCIDENCIA RECIENTE
// -----------------------------------------------------------------

class _IncidenciaReciente extends StatelessWidget {
  final VoidCallback? onTap;
  final String categoria;
  final String detalle;
  final String ubicacion;
  final String fecha;
  final String estado;
  final String tecnico;

  const _IncidenciaReciente({
    this.onTap,
    required this.categoria,
    required this.detalle,
    required this.ubicacion,
    required this.fecha,
    required this.estado,
    required this.tecnico,
  });

  Color get colorEstado {
    switch (estado) {
      case 'En atención':
        return const Color(0xFF2563EB);

      case 'Resuelta':
        return const Color(0xFF16A34A);

      default:
        return const Color(0xFFD97706);
    }
  }

  Color get fondoEstado {
    switch (estado) {
      case 'En atención':
        return const Color(0xFFEFF6FF);

      case 'Resuelta':
        return const Color(0xFFF0FDF4);

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
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,

          padding: const EdgeInsets.all(18),

          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Container(
                    width: 44,
                    height: 44,

                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                    ),

                    child: const Icon(
                      Icons.construction_outlined,
                      color: Color(0xFFD97706),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        Text(
                          categoria,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          ubicacion,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),

                    decoration: BoxDecoration(
                      color: fondoEstado,
                      borderRadius: BorderRadius.circular(20),
                    ),

                    child: Text(
                      estado,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colorEstado,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Text(
                detalle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Color(0xFF374151),
                ),
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  const Icon(
                    Icons.schedule_outlined,
                    size: 16,
                    color: Color(0xFF9CA3AF),
                  ),

                  const SizedBox(width: 5),

                  Expanded(
                    child: Text(
                      fecha,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ],
              ),

              if (tecnico.trim().isNotEmpty) ...[
                const SizedBox(height: 8),

                Row(
                  children: [
                    const Icon(
                      Icons.engineering_outlined,
                      size: 16,
                      color: Color(0xFF9CA3AF),
                    ),

                    const SizedBox(width: 5),

                    Expanded(
                      child: Text(
                        'Asignada a: $tecnico',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
