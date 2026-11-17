import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/sesion_data.dart';
import '../core/push/notificaciones_push_service.dart';

import 'registros_supervisor_page.dart';
import 'solicitudes_excepciones_supervisor_page.dart';
import 'alertas_supervisor_page.dart';
import 'marcar_nfc_danado_page.dart';
import 'gestion_usuarios_page.dart';
import 'gestion_sectores_page.dart';
import 'gestion_asignaciones_page.dart';
import 'perfil_supervisor_jefe_page.dart';
import 'notificaciones_page.dart';

class SupervisorJefeHomePage extends StatefulWidget {
  const SupervisorJefeHomePage({super.key});

  @override
  State<SupervisorJefeHomePage> createState() => _SupervisorJefeHomePageState();
}

class _SupervisorJefeHomePageState extends State<SupervisorJefeHomePage> {
  final SupabaseClient supabase = Supabase.instance.client;

  // =============================================================
  // RESUMEN
  // =============================================================

  int registrosHoy = 0;
  int solicitudesPendientes = 0;
  int alertasPendientes = 0;
  int nfcDanados = 0;

  bool cargandoResumen = true;
  String? errorResumen;

  // =============================================================
  // INIT
  // =============================================================

  @override
  void initState() {
    super.initState();

    cargarResumen();
  }

  // =============================================================
  // CONVERSIÓN SEGURA
  // =============================================================

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

  // =============================================================
  // RESUMEN REAL DESDE SUPABASE
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
      // 1. REGISTROS COMPLETADOS HOY
      // Mismo criterio que el Supervisor: fecha real de término.
      // =========================================================

      final dynamic registrosRespuesta = await supabase.rpc(
        'listar_registros_supervision',
      );

      final List<dynamic> registros = registrosRespuesta is List
          ? registrosRespuesta
          : <dynamic>[];

      final DateTime hoy = DateTime.now();
      int cantidadRegistrosHoy = 0;

      for (final dynamic fila in registros) {
        if (fila is! Map) {
          continue;
        }

        final dynamic valorTermino = fila['fecha_hora_fin'];

        if (valorTermino == null) {
          continue;
        }

        final DateTime? termino = DateTime.tryParse(valorTermino.toString())
            ?.toLocal();

        if (termino != null &&
            termino.year == hoy.year &&
            termino.month == hoy.month &&
            termino.day == hoy.day) {
          cantidadRegistrosHoy++;
        }
      }

      // =========================================================
      // 2. IDENTIFICAR TIPOS DE ALERTA
      // =========================================================

      final List<dynamic> tiposAlertaRaw = await supabase
          .from('tipo_alerta')
          .select(
            'id_tipo_alerta, '
            'nombre_alerta',
          )
          .eq('activo', true);

      int? idTipoCierreExcepcional;
      int? idTipoNfcDanado;

      for (final dynamic fila in tiposAlertaRaw) {
        if (fila is! Map) {
          continue;
        }

        final int? idTipo = aInt(fila['id_tipo_alerta']);

        final String nombre = (fila['nombre_alerta'] ?? '').toString().trim();

        if (idTipo == null) {
          continue;
        }

        if (nombre == 'Cierre excepcional') {
          idTipoCierreExcepcional = idTipo;

          continue;
        }

        if (nombre == 'NFC dañado') {
          idTipoNfcDanado = idTipo;

          continue;
        }
      }

      // =========================================================
      // 3. SOLICITUDES DE CIERRE EXCEPCIONAL PENDIENTES
      // =========================================================

      int solicitudes = 0;

      if (idTipoCierreExcepcional != null) {
        final List<dynamic> solicitudesRaw = await supabase
            .from('alerta')
            .select(
              'id_alerta, '
              'estado',
            )
            .eq('id_tipo_alerta', idTipoCierreExcepcional)
            .inFilter('estado', <String>['Pendiente', 'Leída', 'En atención']);

        solicitudes = solicitudesRaw.length;
      }

      // =========================================================
      // 4. ALERTAS SIN RESOLVER
      // Misma fuente que la bandeja del Supervisor, incluyendo
      // observaciones derivadas a Mantención.
      // =========================================================

      final dynamic alertasRespuesta = await supabase.rpc(
        'listar_alertas_supervision',
      );

      final List<dynamic> alertasRaw = alertasRespuesta is List
          ? alertasRespuesta
          : <dynamic>[];

      int alertas = 0;

      for (final dynamic fila in alertasRaw) {
        if (fila is! Map) {
          continue;
        }

        final String estado = (fila['estado_alerta'] ?? '').toString().trim();

        if (estado == 'Pendiente' ||
            estado == 'Leída' ||
            estado == 'En atención') {
          alertas++;
        }
      }

      // =========================================================
      // 5. NFC DAÑADOS
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

      // El tipo NFC dañado existe también como alerta.
      // No lo contamos dentro de "Alertas" porque ya
      // tiene su indicador propio.
      if (idTipoNfcDanado != null) {
        debugPrint(
          'Tipo alerta NFC dañado: '
          '$idTipoNfcDanado',
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        registrosHoy = cantidadRegistrosHoy;

        solicitudesPendientes = solicitudes;

        alertasPendientes = alertas;

        nfcDanados = cantidadNfcDanados;

        cargandoResumen = false;

        errorResumen = null;
      });
    } catch (e, stackTrace) {
      debugPrint(
        'ERROR cargarResumen Supervisor Jefe: '
        '$e',
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
  // ABRIR PÁGINA Y ACTUALIZAR RESUMEN AL REGRESAR
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
    } catch (e) {
      debugPrint(
        'ERROR cerrarSesion Supervisor Jefe: '
        '$e',
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
        : 'Supervisor Jefe';

    final String primerNombre = SesionData.primerNombreActual.trim().isNotEmpty
        ? SesionData.primerNombreActual
        : 'Supervisor Jefe';

    final String inicial = SesionData.inicialActual.trim().isNotEmpty
        ? SesionData.inicialActual
        : 'S';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      // ===========================================================
      // BARRA SUPERIOR
      // ===========================================================
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

      // ===========================================================
      // MENÚ LATERAL
      // ===========================================================
      drawer: Drawer(
        backgroundColor: Colors.white,

        child: SafeArea(
          child: Column(
            children: [
              // ----------------------------------------------------
              // CABECERA
              // ----------------------------------------------------

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
                      'Administrador del sistema',

                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ----------------------------------------------------
              // MI PERFIL
              // ----------------------------------------------------
              ListTile(
                leading: const Icon(Icons.person_outline),

                title: const Text('Mi perfil'),

                onTap: () {
                  Navigator.pop(context);

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PerfilSupervisorJefePage(),
                    ),
                  );
                },
              ),

              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 8),

                child: Align(
                  alignment: Alignment.centerLeft,

                  child: Text(
                    'ADMINISTRACIÓN',

                    style: TextStyle(
                      fontSize: 12,

                      fontWeight: FontWeight.bold,

                      color: Color(0xFF9CA3AF),

                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),

              // ----------------------------------------------------
              // USUARIOS
              // ----------------------------------------------------
              ListTile(
                leading: const Icon(
                  Icons.people_outline,

                  color: Color(0xFF1565C0),
                ),

                title: const Text('Gestión de usuarios'),

                onTap: () {
                  Navigator.pop(context);

                  abrirPagina(const GestionUsuariosPage());
                },
              ),

              // ----------------------------------------------------
              // SECTORES
              // ----------------------------------------------------
              ListTile(
                leading: const Icon(
                  Icons.location_city_outlined,

                  color: Color(0xFF1565C0),
                ),

                title: const Text('Gestión de sectores'),

                onTap: () {
                  Navigator.pop(context);

                  abrirPagina(const GestionSectoresPage());
                },
              ),

              // ----------------------------------------------------
              // ASIGNACIONES
              // ----------------------------------------------------
              ListTile(
                leading: const Icon(
                  Icons.assignment_ind_outlined,

                  color: Color(0xFF0F766E),
                ),

                title: const Text('Gestión de asignaciones'),

                subtitle: const Text(
                  'Auxiliares, pisos y espacios',

                  style: TextStyle(fontSize: 12),
                ),

                onTap: () {
                  Navigator.pop(context);

                  abrirPagina(const GestionAsignacionesPage());
                },
              ),

              const Spacer(),

              const Divider(),

              // ----------------------------------------------------
              // CERRAR SESIÓN
              // ----------------------------------------------------
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

      // ===========================================================
      // CONTENIDO
      // ===========================================================
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
                    // ===============================================
                    // SALUDO
                    // ===============================================

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
                      'Supervisión y gestión de labores de aseo',

                      style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
                    ),

                    const SizedBox(height: 28),

                    // ===============================================
                    // RESUMEN REAL
                    // ===============================================
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
                                  'Resumen operativo',

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

                          const SizedBox(height: 6),

                          const Text(
                            'Información real registrada en RegiServ.',

                            style: TextStyle(
                              fontSize: 13,

                              color: Color(0xFF6B7280),
                            ),
                          ),

                          const SizedBox(height: 20),

                          Row(
                            children: [
                              Expanded(
                                child: _IndicadorSupervisorJefe(
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
                                child: _IndicadorSupervisorJefe(
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
                                child: _IndicadorSupervisorJefe(
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
                                child: _IndicadorSupervisorJefe(
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

                    // ===============================================
                    // ADMINISTRACIÓN OPERATIVA
                    // ===============================================
                    const Text(
                      'Administración operativa',

                      style: TextStyle(
                        fontSize: 21,

                        fontWeight: FontWeight.bold,

                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Administra la distribución de sectores y espacios entre los Auxiliares.',

                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),

                    const SizedBox(height: 16),

                    _AccionSupervisorJefe(
                      icono: Icons.assignment_ind_outlined,

                      titulo: 'Gestión de asignaciones',

                      descripcion: 'Asigna o quita pisos y espacios de trabajo a los Auxiliares.',

                      color: const Color(0xFF0F766E),

                      onTap: () {
                        abrirPagina(const GestionAsignacionesPage());
                      },
                    ),

                    const SizedBox(height: 28),

                    // ===============================================
                    // GESTIÓN EN TERRENO
                    // ===============================================
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
                      'Revisa la actividad generada por los Auxiliares.',

                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),

                    const SizedBox(height: 16),

                    // ------------------------------------------------
                    // REGISTROS
                    // ------------------------------------------------
                    _AccionSupervisorJefe(
                      icono: Icons.assignment_outlined,

                      titulo: 'Registros de aseo',

                      descripcion:
                          'Consulta las labores realizadas por los Auxiliares.',

                      onTap: () {
                        abrirPagina(const RegistrosSupervisorPage());
                      },
                    ),

                    const SizedBox(height: 12),

                    // ------------------------------------------------
                    // SOLICITUDES
                    // ------------------------------------------------
                    _AccionSupervisorJefe(
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

                    // ------------------------------------------------
                    // ALERTAS
                    // ------------------------------------------------
                    _AccionSupervisorJefe(
                      icono: Icons.notifications_active_outlined,

                      titulo: 'Alertas',

                      descripcion: 'Revisa observaciones y daños que requieren atención.',

                      color: const Color(0xFFDC2626),

                      onTap: () {
                        abrirPagina(const AlertasSupervisorPage());
                      },
                    ),

                    const SizedBox(height: 12),

                    // ------------------------------------------------
                    // NFC DAÑADO
                    // ------------------------------------------------
                    _AccionSupervisorJefe(
                      icono: Icons.nfc_outlined,

                      titulo: 'Marcar NFC dañado',

                      descripcion: 'Informa que una etiqueta NFC física no puede seguir utilizándose.',

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

// =================================================================
// INDICADOR
// =================================================================

class _IndicadorSupervisorJefe extends StatelessWidget {
  final IconData icono;

  final String valor;
  final String titulo;

  final Color color;

  const _IndicadorSupervisorJefe({
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

            maxLines: 1,

            overflow: TextOverflow.ellipsis,

            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// TARJETA DE ACCIÓN
// =================================================================

class _AccionSupervisorJefe extends StatelessWidget {
  final IconData icono;

  final String titulo;
  final String descripcion;

  final VoidCallback onTap;

  final Color color;

  const _AccionSupervisorJefe({
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
                  color: color.withValues(alpha: 0.10),

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
