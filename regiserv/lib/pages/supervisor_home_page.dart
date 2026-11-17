import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/sesion_data.dart';
import '../core/push/notificaciones_push_service.dart';

import 'registros_supervisor_page.dart';
import 'solicitudes_excepciones_supervisor_page.dart';
import 'alertas_supervisor_page.dart';
import 'marcar_nfc_danado_page.dart';
import 'perfil_supervisor_page.dart';
import 'notificaciones_page.dart';

class SupervisorHomePage extends StatefulWidget {
  const SupervisorHomePage({super.key});

  @override
  State<SupervisorHomePage> createState() => _SupervisorHomePageState();
}

class _SupervisorHomePageState extends State<SupervisorHomePage> {
  final SupabaseClient supabase = Supabase.instance.client;

  int registrosHoy = 0;
  int solicitudesPendientes = 0;
  int alertasPendientes = 0;
  int nfcDanados = 0;

  bool cargandoResumen = true;
  String? errorResumen;

  @override
  void initState() {
    super.initState();
    cargarResumen();
  }

  int? aInt(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor.toString());
  }

  DateTime? convertirFecha(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is DateTime) {
      return valor.toLocal();
    }

    final DateTime? fecha = DateTime.tryParse(valor.toString());

    return fecha?.toLocal();
  }

  bool esHoy(DateTime? fecha) {
    if (fecha == null) {
      return false;
    }

    final DateTime ahora = DateTime.now();

    return fecha.year == ahora.year &&
        fecha.month == ahora.month &&
        fecha.day == ahora.day;
  }

  // =============================================================
  // CARGAR RESUMEN REAL
  // =============================================================

  Future<void> cargarResumen() async {
    if (!mounted) {
      return;
    }

    setState(() {
      cargandoResumen = true;
      errorResumen = null;
    });

    try {
      // =========================================================
      // 1. REGISTROS FINALIZADOS HOY
      // =========================================================

      final dynamic registrosRespuesta = await supabase.rpc(
        'listar_registros_supervision',
      );

      final List<dynamic> registros = registrosRespuesta is List
          ? registrosRespuesta
          : <dynamic>[];

      int cantidadRegistrosHoy = 0;

      for (final dynamic fila in registros) {
        if (fila is! Map) {
          continue;
        }

        final DateTime? termino = convertirFecha(fila['fecha_hora_fin']);

        if (esHoy(termino)) {
          cantidadRegistrosHoy++;
        }
      }

      // =========================================================
      // 2. SOLICITUDES DE CIERRE EXCEPCIONAL PENDIENTES
      // =========================================================

      final dynamic solicitudesRespuesta = await supabase.rpc(
        'listar_solicitudes_cierre_excepcional',
      );

      final List<dynamic> solicitudes = solicitudesRespuesta is List
          ? solicitudesRespuesta
          : <dynamic>[];

      final int cantidadSolicitudes = solicitudes.length;

      // =========================================================
      // 3. ALERTAS / OBSERVACIONES POR ATENDER
      // =========================================================

      final dynamic alertasRespuesta = await supabase.rpc(
        'listar_alertas_supervision',
      );

      final List<dynamic> alertas = alertasRespuesta is List
          ? alertasRespuesta
          : <dynamic>[];

      int cantidadAlertas = 0;

      for (final dynamic fila in alertas) {
        if (fila is! Map) {
          continue;
        }

        final String estado = (fila['estado_alerta'] ?? '').toString().trim();

        if (estado == 'Pendiente' ||
            estado == 'Leída' ||
            estado == 'En atención') {
          cantidadAlertas++;
        }
      }

      // =========================================================
      // 4. NFC DAÑADOS VIGENTES
      // =========================================================

      final List<dynamic> estadosNfcRaw = await supabase
          .from('estado_nfc')
          .select(
            'id_estado_nfc, '
            'nombre_estado',
          )
          .eq('nombre_estado', 'Dañado');

      int cantidadNfcDanados = 0;

      if (estadosNfcRaw.isNotEmpty) {
        final dynamic fila = estadosNfcRaw.first;

        if (fila is Map) {
          final int? idEstadoDanado = aInt(fila['id_estado_nfc']);

          if (idEstadoDanado != null) {
            final List<dynamic> nfcRaw = await supabase
                .from('nfc')
                .select(
                  'id_nfc, '
                  'fecha_retiro',
                )
                .eq('id_estado_nfc', idEstadoDanado)
                .isFilter('fecha_retiro', null);

            cantidadNfcDanados = nfcRaw.length;
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        registrosHoy = cantidadRegistrosHoy;

        solicitudesPendientes = cantidadSolicitudes;

        alertasPendientes = cantidadAlertas;

        nfcDanados = cantidadNfcDanados;

        cargandoResumen = false;
        errorResumen = null;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'ERROR cargarResumen Supervisor: '
        '$error',
      );
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        registrosHoy = 0;
        solicitudesPendientes = 0;
        alertasPendientes = 0;
        nfcDanados = 0;

        cargandoResumen = false;
        errorResumen = 'No fue posible cargar el resumen.';
      });
    }
  }

  // =============================================================
  // ABRIR PÁGINA Y ACTUALIZAR AL REGRESAR
  // =============================================================

  Future<void> abrirPagina(Widget pagina) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => pagina),
    );

    if (!mounted) {
      return;
    }

    await cargarResumen();
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
        'ERROR cerrarSesion Supervisor: '
        '$error',
      );
    }

    SesionData.cerrarSesion();

    if (!mounted) {
      return;
    }

    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final String nombre = SesionData.nombreActual.trim().isNotEmpty
        ? SesionData.nombreActual
        : 'Supervisor';

    final String primerNombre = SesionData.primerNombreActual.trim().isNotEmpty
        ? SesionData.primerNombreActual
        : 'Supervisor';

    final String inicial = SesionData.inicialActual.trim().isNotEmpty
        ? SesionData.inicialActual
        : 'S';

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
            onPressed: cargandoResumen ? null : cargarResumen,
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
                      'Supervisor de terreno',
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Mi perfil'),
                onTap: () {
                  Navigator.pop(context);

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PerfilSupervisorPage(),
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
          onRefresh: cargarResumen,

          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),

            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 650),

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
                      'Supervisión de labores de aseo',
                      style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
                    ),

                    const SizedBox(height: 28),

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

                              if (cargandoResumen)
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
                                child: _IndicadorSupervisor(
                                  icono: Icons.assignment_turned_in_outlined,
                                  valor: cargandoResumen
                                      ? '...'
                                      : '$registrosHoy',
                                  titulo: 'Registros hoy',
                                  color: const Color(0xFF1565C0),
                                ),
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: _IndicadorSupervisor(
                                  icono: Icons.support_agent_outlined,
                                  valor: cargandoResumen
                                      ? '...'
                                      : '$solicitudesPendientes',
                                  titulo: 'Solicitudes',
                                  color: const Color(0xFFD97706),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          Row(
                            children: [
                              Expanded(
                                child: _IndicadorSupervisor(
                                  icono: Icons.notifications_active_outlined,
                                  valor: cargandoResumen
                                      ? '...'
                                      : '$alertasPendientes',
                                  titulo: 'Alertas',
                                  color: const Color(0xFFDC2626),
                                ),
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: _IndicadorSupervisor(
                                  icono: Icons.nfc_outlined,
                                  valor: cargandoResumen
                                      ? '...'
                                      : '$nfcDanados',
                                  titulo: 'NFC dañados',
                                  color: const Color(0xFF7C3AED),
                                ),
                              ),
                            ],
                          ),

                          if (errorResumen != null) ...[
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
                                      errorResumen!,
                                      style: const TextStyle(
                                        color: Color(0xFF9A3412),
                                      ),
                                    ),
                                  ),

                                  IconButton(
                                    onPressed: cargarResumen,
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

                    const Text(
                      'Gestión en terreno',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Selecciona una opción para revisar o gestionar las labores.',
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),

                    const SizedBox(height: 16),

                    _AccionSupervisor(
                      icono: Icons.assignment_outlined,
                      titulo: 'Registros de aseo',
                      descripcion:
                          'Consulta las labores realizadas por los Auxiliares.',
                      onTap: () {
                        abrirPagina(const RegistrosSupervisorPage());
                      },
                    ),

                    const SizedBox(height: 12),

                    _AccionSupervisor(
                      icono: Icons.support_agent_outlined,
                      titulo: 'Solicitudes y excepciones',
                      descripcion: 'Revisa solicitudes de cierre excepcional enviadas por los Auxiliares.',
                      color: const Color(0xFFD97706),
                      onTap: () {
                        abrirPagina(
                          const SolicitudesExcepcionesSupervisorPage(),
                        );
                      },
                    ),

                    const SizedBox(height: 12),

                    _AccionSupervisor(
                      icono: Icons.notifications_active_outlined,
                      titulo: 'Alertas',
                      descripcion:
                          'Revisa observaciones que requieren atención.',
                      color: const Color(0xFFDC2626),
                      onTap: () {
                        abrirPagina(const AlertasSupervisorPage());
                      },
                    ),

                    const SizedBox(height: 12),

                    _AccionSupervisor(
                      icono: Icons.nfc_outlined,
                      titulo: 'Marcar NFC dañado',
                      descripcion: 'Informa que un NFC físico no puede seguir utilizándose.',
                      color: const Color(0xFF7C3AED),
                      onTap: () {
                        abrirPagina(const MarcarNfcDanadoPage());
                      },
                    ),
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

class _IndicadorSupervisor extends StatelessWidget {
  final IconData icono;
  final String valor;
  final String titulo;
  final Color color;

  const _IndicadorSupervisor({
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
// TARJETA DE ACCIÓN
// -----------------------------------------------------------------

class _AccionSupervisor extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String descripcion;
  final VoidCallback onTap;
  final Color color;

  const _AccionSupervisor({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.onTap,
    this.color = const Color(0xFF1565C0),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),

      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),

        child: Container(
          padding: const EdgeInsets.all(18),

          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),

            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),

          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,

                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),

                child: Icon(icono, color: color),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      descripcion,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }
}
