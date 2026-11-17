import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/storage/hive_local_storage.dart';
import '../data/sesion_data.dart';

import 'labores_disponibles_page.dart';
import 'historial_auxiliar_page.dart';
import 'sincronizacion_auxiliar_page.dart';
import 'perfil_auxiliar_page.dart';
import 'mis_sectores_auxiliar_page.dart';

class AuxiliarHomePage extends StatefulWidget {
  const AuxiliarHomePage({super.key});

  @override
  State<AuxiliarHomePage> createState() => _AuxiliarHomePageState();
}

class _AuxiliarHomePageState extends State<AuxiliarHomePage> {
  int indiceSeleccionado = 1;

  final SupabaseClient supabase = Supabase.instance.client;

  // =============================================================
  // ASIGNACIONES
  // =============================================================

  int pisosAsignados = 0;
  int espaciosAsignados = 0;

  bool cargandoSectores = true;
  String? errorSectores;

  // =============================================================
  // RESUMEN DE HOY
  // =============================================================

  int laboresRealizadasHoy = 0;

  String ultimaLaborHoy = '—';

  int pendientesSincronizacion = 0;

  bool cargandoResumenHoy = true;
  String? errorResumenHoy;

  bool cargandoSincronizacion = true;
  String? errorSincronizacion;

  // =============================================================
  // INIT
  // =============================================================

  @override
  void initState() {
    super.initState();

    cargarDatosHome();
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
  // CARGAR TODO EL HOME
  // =============================================================

  Future<void> cargarDatosHome() async {
    await Future.wait([
      cargarResumenSectores(),
      cargarResumenHoy(),
      cargarPendientesSincronizacion(),
    ]);
  }

  // =============================================================
  // RESUMEN REAL DE ASIGNACIONES
  // =============================================================

  Future<void> cargarResumenSectores() async {
    if (!mounted) {
      return;
    }

    setState(() {
      cargandoSectores = true;
      errorSectores = null;
    });

    try {
      final usuarioAuth = supabase.auth.currentUser;

      if (usuarioAuth == null) {
        throw Exception('No existe una sesión autenticada en Supabase.');
      }

      final String idUsuario = usuarioAuth.id;

      // ---------------------------------------------------------
      // PISOS VIGENTES
      // ---------------------------------------------------------

      final List<dynamic> respuestaPisos = await supabase
          .from('piso_trabajador')
          .select('id_piso')
          .eq('id_usuario', idUsuario)
          .isFilter('fecha_fin', null);

      final Set<int> idsPisos = <int>{};

      for (final dynamic registro in respuestaPisos) {
        if (registro is! Map) {
          continue;
        }

        final int? id = aInt(registro['id_piso']);

        if (id != null) {
          idsPisos.add(id);
        }
      }

      // ---------------------------------------------------------
      // ESPACIOS VIGENTES
      // ---------------------------------------------------------

      final List<dynamic> respuestaEspacios = await supabase
          .from('espacio_trabajador')
          .select('id_espacio')
          .eq('id_usuario', idUsuario)
          .isFilter('fecha_ter', null);

      int cantidadEspacios = 0;

      for (final dynamic registro in respuestaEspacios) {
        if (registro is Map && registro['id_espacio'] != null) {
          cantidadEspacios++;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        pisosAsignados = idsPisos.length;

        espaciosAsignados = cantidadEspacios;

        cargandoSectores = false;

        errorSectores = null;
      });
    } catch (e) {
      debugPrint('ERROR cargarResumenSectores: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        pisosAsignados = 0;
        espaciosAsignados = 0;

        cargandoSectores = false;

        errorSectores = 'No fue posible consultar las asignaciones.';
      });
    }
  }

  // =============================================================
  // RESUMEN REAL DE HOY
  // =============================================================

  Future<void> cargarResumenHoy() async {
    if (!mounted) {
      return;
    }

    setState(() {
      cargandoResumenHoy = true;
      errorResumenHoy = null;
    });

    try {
      final usuarioAuth = supabase.auth.currentUser;

      if (usuarioAuth == null) {
        throw Exception('No existe una sesión autenticada.');
      }

      final String idUsuario = usuarioAuth.id;

      // ---------------------------------------------------------
      // INICIO Y FIN DEL DÍA LOCAL
      // ---------------------------------------------------------

      final DateTime ahora = DateTime.now();

      final DateTime inicioDiaLocal = DateTime(
        ahora.year,
        ahora.month,
        ahora.day,
      );

      final DateTime finDiaLocal = inicioDiaLocal.add(const Duration(days: 1));

      final String inicioDiaUtc = inicioDiaLocal.toUtc().toIso8601String();

      final String finDiaUtc = finDiaLocal.toUtc().toIso8601String();

      // ---------------------------------------------------------
      // REGISTROS FINALIZADOS HOY DEL AUXILIAR
      // ---------------------------------------------------------

      final List<dynamic> registrosRaw = await supabase
          .from('registro_aseo')
          .select(
            'id_registro_aseo, '
            'id_espacio, '
            'fecha_hora_inicio, '
            'fecha_hora_fin, '
            'estado_sincronizacion',
          )
          .eq('id_usuario', idUsuario)
          .gte('fecha_hora_fin', inicioDiaUtc)
          .lt('fecha_hora_fin', finDiaUtc)
          .order('fecha_hora_fin', ascending: false);

      final Map<int, Map<String, dynamic>> registrosPorId = {};

      final List<int> idsRegistros = [];

      for (final dynamic fila in registrosRaw) {
        if (fila is! Map) {
          continue;
        }

        final Map<String, dynamic> registro = Map<String, dynamic>.from(fila);

        final int? idRegistro = aInt(registro['id_registro_aseo']);

        if (idRegistro == null) {
          continue;
        }

        registrosPorId[idRegistro] = registro;

        idsRegistros.add(idRegistro);
      }

      // ---------------------------------------------------------
      // IDENTIFICAR CUÁLES TIENEN ESTADO FINAL
      // ---------------------------------------------------------

      final Set<int> registrosCompletados = <int>{};

      int? idUltimoRegistroCompletado;

      if (idsRegistros.isNotEmpty) {
        final List<dynamic> estadosRaw = await supabase
            .from('registro_estado')
            .select(
              'id_registro_aseo, '
              'fecha_hora_ini_estado',
            )
            .inFilter('id_registro_aseo', idsRegistros)
            .order('fecha_hora_ini_estado', ascending: false);

        for (final dynamic fila in estadosRaw) {
          if (fila is! Map) {
            continue;
          }

          final int? idRegistro = aInt(fila['id_registro_aseo']);

          if (idRegistro == null) {
            continue;
          }

          registrosCompletados.add(idRegistro);

          // Como la consulta viene ordenada
          // de más reciente a más antigua,
          // el primero es la última labor.
          idUltimoRegistroCompletado ??= idRegistro;
        }
      }

      // ---------------------------------------------------------
      // ÚLTIMO ESPACIO COMPLETADO
      // ---------------------------------------------------------

      String ultimaLabor = '—';

      if (idUltimoRegistroCompletado != null) {
        final Map<String, dynamic>? ultimoRegistro =
            registrosPorId[idUltimoRegistroCompletado];

        final int? idEspacio = aInt(ultimoRegistro?['id_espacio']);

        if (idEspacio != null) {
          final dynamic espacioRaw = await supabase
              .from('espacio')
              .select('codigo')
              .eq('id_espacio', idEspacio)
              .single();

          if (espacioRaw is Map) {
            final String codigo = (espacioRaw['codigo'] ?? '')
                .toString()
                .trim();

            if (codigo.isNotEmpty) {
              ultimaLabor = codigo;
            }
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        laboresRealizadasHoy = registrosCompletados.length;

        ultimaLaborHoy = ultimaLabor;

        cargandoResumenHoy = false;

        errorResumenHoy = null;
      });
    } catch (e, stackTrace) {
      debugPrint('ERROR cargarResumenHoy: $e');

      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        laboresRealizadasHoy = 0;

        ultimaLaborHoy = '—';

        cargandoResumenHoy = false;

        errorResumenHoy = 'No fue posible cargar el resumen.';
      });
    }
  }

  // =============================================================
  // PENDIENTES REALES DE SINCRONIZACIÓN
  // =============================================================

  Future<void> cargarPendientesSincronizacion() async {
    if (!mounted) {
      return;
    }

    setState(() {
      cargandoSincronizacion = true;
      errorSincronizacion = null;
    });

    try {
      final String? idUsuarioSesion = SesionData.usuarioIdActual;

      final String? idUsuarioAuth = supabase.auth.currentUser?.id;

      final String? idUsuario =
          idUsuarioSesion != null && idUsuarioSesion.trim().isNotEmpty
          ? idUsuarioSesion
          : idUsuarioAuth;

      if (idUsuario == null || idUsuario.trim().isEmpty) {
        throw Exception('No fue posible identificar al usuario actual.');
      }

      final List<Map<String, dynamic>> pendientes = HiveLocalStorage.instance
          .listarPendientes(idUsuario);

      if (!mounted) {
        return;
      }

      setState(() {
        pendientesSincronizacion = pendientes.length;

        cargandoSincronizacion = false;
        errorSincronizacion = null;
      });
    } catch (e) {
      debugPrint('ERROR cargarPendientesSincronizacion: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        pendientesSincronizacion = 0;

        cargandoSincronizacion = false;

        errorSincronizacion =
            'No fue posible revisar los registros pendientes.';
      });
    }
  }

  // =============================================================
  // MIS SECTORES
  // =============================================================

  Future<void> abrirMisSectores() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MisSectoresAuxiliarPage()),
    );

    if (!mounted) {
      return;
    }

    await cargarDatosHome();
  }

  // =============================================================
  // LABORES DISPONIBLES
  // =============================================================

  Future<void> abrirLaboresDisponibles() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LaboresDisponiblesPage()),
    );

    if (!mounted) {
      return;
    }

    // Al volver refrescamos todo:
    // asignaciones + labores del día.
    await cargarDatosHome();
  }

  // =============================================================
  // SINCRONIZACIÓN
  // =============================================================

  Future<void> abrirSincronizacion() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SincronizacionAuxiliarPage(),
      ),
    );

    if (!mounted) {
      return;
    }

    await cargarPendientesSincronizacion();
  }

  // =============================================================
  // CERRAR SESIÓN
  // =============================================================

  Future<void> cerrarSesion() async {
    try {
      await supabase.auth.signOut();
    } catch (e) {
      debugPrint('ERROR cerrarSesion Supabase: $e');
    }

    SesionData.cerrarSesion();

    if (!mounted) {
      return;
    }

    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  // =============================================================
  // DATOS VISUALES DE SINCRONIZACIÓN
  // =============================================================

  String get textoSincronizacion {
    if (cargandoSincronizacion) {
      return 'Verificando sincronización...';
    }

    if (errorSincronizacion != null) {
      return 'No fue posible verificar la sincronización.';
    }

    if (pendientesSincronizacion == 0) {
      return 'Todos tus registros están sincronizados.';
    }

    if (pendientesSincronizacion == 1) {
      return 'Tienes 1 registro pendiente de sincronización.';
    }

    return 'Tienes $pendientesSincronizacion registros pendientes de sincronización.';
  }

  Color get fondoSincronizacion {
    if (cargandoSincronizacion) {
      return const Color(0xFFF3F4F6);
    }

    if (errorSincronizacion != null || pendientesSincronizacion > 0) {
      return const Color(0xFFFFF7ED);
    }

    return const Color(0xFFF0FDF4);
  }

  Color get colorSincronizacion {
    if (cargandoSincronizacion) {
      return const Color(0xFF6B7280);
    }

    if (errorSincronizacion != null || pendientesSincronizacion > 0) {
      return const Color(0xFFC2410C);
    }

    return const Color(0xFF166534);
  }

  IconData get iconoSincronizacion {
    if (cargandoSincronizacion) {
      return Icons.sync;
    }

    if (errorSincronizacion != null) {
      return Icons.error_outline;
    }

    if (pendientesSincronizacion > 0) {
      return Icons.cloud_off_outlined;
    }

    return Icons.cloud_done_outlined;
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final usuario = SesionData.usuarioActual;

    // -------------------------------------------------------------
    // SIN SESIÓN
    // -------------------------------------------------------------

    if (usuario == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_off_outlined,
                size: 55,
                color: Color(0xFF9CA3AF),
              ),

              const SizedBox(height: 14),

              const Text('No existe una sesión activa.'),

              const SizedBox(height: 14),

              ElevatedButton(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/',
                    (route) => false,
                  );
                },
                child: const Text('Volver al login'),
              ),
            ],
          ),
        ),
      );
    }

    final String nombre = SesionData.nombreActual;

    final String primerNombre = SesionData.primerNombreActual;

    final String inicial = SesionData.inicialActual;

    final bool tieneSectores = espaciosAsignados > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      // ===========================================================
      // APPBAR
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
      ),

      // ===========================================================
      // DRAWER
      // ===========================================================
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
                      'Auxiliar de aseo',
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ---------------------------------------------------
              // PERFIL
              // ---------------------------------------------------
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Mi perfil'),
                onTap: () {
                  Navigator.pop(context);

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PerfilAuxiliarPage(),
                    ),
                  );
                },
              ),

              // ---------------------------------------------------
              // MIS SECTORES
              // ---------------------------------------------------
              ListTile(
                leading: const Icon(
                  Icons.location_city_outlined,
                  color: Color(0xFF0F766E),
                ),
                title: const Text('Mis sectores asignados'),
                subtitle: Text(
                  cargandoSectores
                      ? 'Cargando...'
                      : '$espaciosAsignados espacios',
                ),
                onTap: () {
                  Navigator.pop(context);

                  abrirMisSectores();
                },
              ),

              const Spacer(),

              const Divider(),

              // ---------------------------------------------------
              // CERRAR SESIÓN
              // ---------------------------------------------------
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
          onRefresh: cargarDatosHome,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
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
                      'Auxiliar de aseo',
                      style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
                    ),

                    const SizedBox(height: 28),

                    // ===============================================
                    // RESUMEN REAL DE HOY
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
                          const Text(
                            'Resumen de hoy',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1F2937),
                            ),
                          ),

                          const SizedBox(height: 20),

                          Row(
                            children: [
                              Expanded(
                                child: _ResumenItem(
                                  icono: Icons.cleaning_services_outlined,
                                  titulo: cargandoResumenHoy
                                      ? '...'
                                      : '$laboresRealizadasHoy',
                                  subtitulo: laboresRealizadasHoy == 1
                                      ? 'Labor realizada'
                                      : 'Labores realizadas',
                                ),
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: _ResumenItem(
                                  icono: Icons.location_on_outlined,
                                  titulo: cargandoResumenHoy
                                      ? '...'
                                      : ultimaLaborHoy,
                                  subtitulo: 'Última labor',
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: fondoSincronizacion,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  iconoSincronizacion,
                                  color: colorSincronizacion,
                                ),

                                const SizedBox(width: 10),

                                Expanded(
                                  child: Text(
                                    textoSincronizacion,
                                    style: TextStyle(
                                      color: colorSincronizacion,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (errorResumenHoy != null) ...[
                            const SizedBox(height: 8),

                            TextButton.icon(
                              onPressed: cargarResumenHoy,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar resumen'),
                            ),
                          ],

                          if (errorSincronizacion != null) ...[
                            const SizedBox(height: 8),

                            TextButton.icon(
                              onPressed: cargarPendientesSincronizacion,
                              icon: const Icon(Icons.sync),
                              label: const Text('Reintentar sincronización'),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ===============================================
                    // MIS SECTORES
                    // ===============================================
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        onTap: abrirMisSectores,
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDFA),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Icon(
                                  Icons.assignment_ind_outlined,
                                  color: Color(0xFF0F766E),
                                  size: 27,
                                ),
                              ),

                              const SizedBox(width: 14),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Mis sectores asignados',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      cargandoSectores
                                          ? 'Cargando sectores...'
                                          : errorSectores != null
                                          ? 'No fue posible cargar tus sectores'
                                          : pisosAsignados == 0 ||
                                                espaciosAsignados == 0
                                          ? 'No tienes sectores asignados'
                                          : '$pisosAsignados ${pisosAsignados == 1 ? 'piso' : 'pisos'} · '
                                                '$espaciosAsignados ${espaciosAsignados == 1 ? 'espacio' : 'espacios'}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const Icon(
                                Icons.chevron_right,
                                color: Color(0xFF9CA3AF),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ===============================================
                    // ESTADO
                    // ===============================================
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cargandoSectores
                            ? const Color(0xFFF3F4F6)
                            : errorSectores != null
                            ? const Color(0xFFFFF7ED)
                            : tieneSectores
                            ? const Color(0xFFEFF6FF)
                            : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                cargandoSectores
                                    ? Icons.sync
                                    : errorSectores != null
                                    ? Icons.error_outline
                                    : tieneSectores
                                    ? Icons.nfc
                                    : Icons.warning_amber_outlined,
                                color: cargandoSectores
                                    ? const Color(0xFF6B7280)
                                    : errorSectores != null
                                    ? const Color(0xFFEA580C)
                                    : tieneSectores
                                    ? const Color(0xFF1565C0)
                                    : const Color(0xFFD97706),
                              ),

                              const SizedBox(width: 10),

                              Expanded(
                                child: Text(
                                  cargandoSectores
                                      ? 'Verificando sectores'
                                      : errorSectores != null
                                      ? 'No fue posible verificar tus sectores'
                                      : tieneSectores
                                      ? 'Listo para comenzar'
                                      : 'Sin sectores asignados',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          Text(
                            cargandoSectores
                                ? 'Estamos consultando tus asignaciones vigentes.'
                                : errorSectores != null
                                ? 'No se pudieron consultar tus asignaciones. Desliza hacia abajo para volver a intentarlo.'
                                : tieneSectores
                                ? 'Tienes $espaciosAsignados espacios asignados. '
                                      'Para iniciar una nueva labor, selecciona "Iniciar labor", '
                                      'elige uno de tus espacios disponibles y luego valida el NFC y tu ubicación.'
                                : 'Actualmente no tienes espacios bajo tu responsabilidad. '
                                      'Consulta con tu Supervisor Jefe.',
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),

      // ===========================================================
      // NAVEGACIÓN INFERIOR
      // ===========================================================
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: indiceSeleccionado,
        selectedItemColor: const Color(0xFF1565C0),
        unselectedItemColor: const Color(0xFF6B7280),
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,

        onTap: (indice) {
          setState(() {
            indiceSeleccionado = indice;
          });

          if (indice == 0) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const HistorialAuxiliarPage(),
              ),
            );
          }

          if (indice == 1) {
            abrirLaboresDisponibles();
          }

          if (indice == 2) {
            abrirSincronizacion();
          }
        },

        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Historial',
          ),

          BottomNavigationBarItem(
            icon: Icon(Icons.nfc),
            label: 'Iniciar labor',
          ),

          BottomNavigationBarItem(
            icon: Icon(Icons.cloud_sync_outlined),
            label: 'Sincronización',
          ),
        ],
      ),
    );
  }
}

// =================================================================
// ITEM RESUMEN
// =================================================================

class _ResumenItem extends StatelessWidget {
  final IconData icono;

  final String titulo;
  final String subtitulo;

  const _ResumenItem({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
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
          Icon(icono, color: const Color(0xFF1565C0), size: 26),

          const SizedBox(height: 12),

          Text(
            titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),

          const SizedBox(height: 3),

          Text(
            subtitulo,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}
