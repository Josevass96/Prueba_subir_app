import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/remote/supabase_remote_backend.dart';
import '../core/storage/hive_local_storage.dart';
import '../core/sync/sincronizacion_service.dart';
import '../core/sync/registro_final_fallback_service.dart';
import '../data/sesion_data.dart';

class SincronizacionAuxiliarPage extends StatefulWidget {
  const SincronizacionAuxiliarPage({super.key});

  @override
  State<SincronizacionAuxiliarPage> createState() =>
      _SincronizacionAuxiliarPageState();
}

class _SincronizacionAuxiliarPageState
    extends State<SincronizacionAuxiliarPage> {
  List<Map<String, dynamic>> registrosPendientes = <Map<String, dynamic>>[];

  bool cargando = true;
  bool sincronizando = false;
  String? errorCarga;

  // Disponibilidad REAL de Supabase (no solamente de Wi-Fi/datos).
  bool? servidorResponde;
  bool comprobandoServidor = false;

  late final SincronizacionService _sincronizacionService;
  Timer? _refrescoLocal;

  @override
  void initState() {
    super.initState();

    _sincronizacionService = SincronizacionService(
      localStorage: HiveLocalStorage.instance,
      remoteBackend: SupabaseRemoteBackend(Supabase.instance.client),
    );

    _cargarPendientes();
    _comprobarServidor();

    // Refleja en pantalla los cambios de Hive realizados por la
    // sincronización automática sin hacer consultas de red adicionales.
    _refrescoLocal = Timer.periodic(const Duration(seconds: 5), (_) {
      _refrescarPendientesSilencioso();
    });
  }

  @override
  void dispose() {
    _refrescoLocal?.cancel();
    super.dispose();
  }

  void _refrescarPendientesSilencioso() {
    if (!mounted || cargando || sincronizando) return;
    final idUsuario = _idUsuarioActual;
    if (idUsuario == null) return;
    try {
      final nuevos = HiveLocalStorage.instance.listarPendientes(idUsuario);
      String resumen(List<Map<String, dynamic>> items) => items
          .map(
            (e) =>
                '${e['id_local']}|${e['estado']}|${e['intentos']}|${e['ultimo_error']}',
          )
          .join(';');
      if (resumen(nuevos) != resumen(registrosPendientes)) {
        setState(() => registrosPendientes = nuevos);
      }
    } catch (error) {
      debugPrint('REGISERV: no se pudo refrescar la cola local: $error');
    }
  }

  Future<void> _comprobarServidor() async {
    if (!mounted) return;
    setState(() => comprobandoServidor = true);
    final bool disponible = await RegistroFinalFallbackService(
      localStorage: HiveLocalStorage.instance,
      supabase: Supabase.instance.client,
    ).backendDisponible();
    if (!mounted) return;
    setState(() {
      servidorResponde = disponible;
      comprobandoServidor = false;
    });
  }

  Future<void> _actualizarTodo() async {
    await Future.wait([_cargarPendientes(), _comprobarServidor()]);
  }

  String? get _idUsuarioActual {
    final String? idSesion = SesionData.usuarioIdActual;

    if (idSesion != null && idSesion.trim().isNotEmpty) {
      return idSesion;
    }

    return Supabase.instance.client.auth.currentUser?.id;
  }

  Future<void> _cargarPendientes() async {
    try {
      final String? idUsuario = _idUsuarioActual;

      if (idUsuario == null || idUsuario.trim().isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          registrosPendientes = <Map<String, dynamic>>[];
          cargando = false;
          errorCarga = 'No fue posible identificar al usuario actual.';
        });

        return;
      }

      final List<Map<String, dynamic>> pendientes = HiveLocalStorage.instance
          .listarPendientes(idUsuario);

      if (!mounted) {
        return;
      }

      setState(() {
        registrosPendientes = pendientes;
        cargando = false;
        errorCarga = null;
      });
    } catch (error) {
      debugPrint('ERROR CARGANDO PENDIENTES DE SINCRONIZACIÓN: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        registrosPendientes = <Map<String, dynamic>>[];
        cargando = false;
        errorCarga = 'No fue posible cargar los registros pendientes.';
      });
    }
  }

  Future<void> _sincronizarAhora() async {
    if (sincronizando) {
      return;
    }

    final String? idUsuario = _idUsuarioActual;

    if (idUsuario == null || idUsuario.trim().isEmpty) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible identificar al usuario actual.'),
        ),
      );

      return;
    }

    final List<Map<String, dynamic>> pendientesAntes = HiveLocalStorage.instance
        .listarPendientes(idUsuario);

    if (pendientesAntes.isEmpty) {
      await _cargarPendientes();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay registros pendientes de sincronización.'),
        ),
      );

      return;
    }

    // El bloqueo de SincronizacionService es compartido
    // entre la sincronización automática y la manual.
    if (_sincronizacionService.sincronizando) {
      await _cargarPendientes();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya hay una sincronización en curso.')),
      );

      return;
    }

    setState(() {
      sincronizando = true;
    });

    try {
      final SincronizacionResultado resultado = await _sincronizacionService
          .sincronizarPendientes(idUsuario: idUsuario);

      await _actualizarTodo();

      if (!mounted) {
        return;
      }

      final int restantes = registrosPendientes.length;

      String mensaje;

      if (resultado.backendNoDisponible) {
        mensaje =
            'No fue posible conectar con el servidor. '
            'Los registros permanecen guardados en el teléfono.';
      } else if (resultado.conError > 0) {
        mensaje =
            'Sincronizados: ${resultado.sincronizados}. '
            'Con error: ${resultado.conError}. '
            'Pendientes: $restantes.';
      } else if (resultado.sincronizados > 0) {
        mensaje = resultado.sincronizados == 1
            ? 'Se sincronizó 1 registro correctamente.'
            : 'Se sincronizaron ${resultado.sincronizados} '
                  'registros correctamente.';
      } else if (restantes == 0) {
        mensaje = 'Todo está sincronizado.';
      } else {
        mensaje =
            'No se procesaron registros en este intento. '
            'Puedes volver a intentarlo.';
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensaje)));
    } catch (error) {
      debugPrint('ERROR SINCRONIZACIÓN MANUAL: $error');

      await _actualizarTodo();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible completar la sincronización.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          sincronizando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool todoSincronizado =
        !cargando && errorCarga == null && registrosPendientes.isEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,

        title: const Text(
          'Sincronización',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),

        actions: [
          IconButton(
            onPressed: cargando ? null : _actualizarTodo,
            tooltip: 'Actualizar estado y conexión',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _actualizarTodo,

          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),

            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),

            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ------------------------------------------------
                    // TÍTULO
                    // ------------------------------------------------

                    const Text(
                      'Estado de tus registros',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Los registros pendientes se sincronizarán '
                      'automáticamente cuando vuelva la conexión.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Color(0xFF6B7280),
                      ),
                    ),

                    const SizedBox(height: 16),
                    // Indicador informativo: estar conectado a Wi-Fi no
                    // garantiza el acceso al servidor de Supabase.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            comprobandoServidor
                                ? Icons.sync
                                : servidorResponde == true
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined,
                            color:
                                servidorResponde == true && !comprobandoServidor
                                ? const Color(0xFF15803D)
                                : const Color(0xFFB45309),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              comprobandoServidor
                                  ? 'Comprobando acceso al servidor...'
                                  : servidorResponde == true
                                  ? 'Supabase responde. Puedes intentar sincronizar.'
                                  : 'No se puede contactar con Supabase por ahora. Tus pendientes están guardados.',
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ------------------------------------------------
                    // CARGANDO
                    // ------------------------------------------------
                    if (cargando)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 44),
                          child: CircularProgressIndicator(),
                        ),
                      ),

                    // ------------------------------------------------
                    // ERROR DE CARGA
                    // ------------------------------------------------
                    if (!cargando && errorCarga != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),

                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),

                        child: Column(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 42,
                              color: Color(0xFFDC2626),
                            ),

                            const SizedBox(height: 10),

                            Text(
                              errorCarga!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF991B1B)),
                            ),

                            const SizedBox(height: 14),

                            OutlinedButton.icon(
                              onPressed: _cargarPendientes,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),

                    // ------------------------------------------------
                    // TODO SINCRONIZADO
                    // ------------------------------------------------
                    if (todoSincronizado)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),

                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(18),

                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),

                        child: const Column(
                          children: [
                            Icon(
                              Icons.cloud_done_outlined,
                              size: 52,
                              color: Color(0xFF16A34A),
                            ),

                            SizedBox(height: 14),

                            Text(
                              'Todo está sincronizado',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF166534),
                              ),
                            ),

                            SizedBox(height: 8),

                            Text(
                              'No tienes registros pendientes '
                              'de sincronización.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF15803D)),
                            ),
                          ],
                        ),
                      ),

                    // ------------------------------------------------
                    // REGISTROS REALES DE HIVE
                    // ------------------------------------------------
                    if (!cargando &&
                        errorCarga == null &&
                        registrosPendientes.isNotEmpty) ...[
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
                              Icons.cloud_off_outlined,
                              color: Color(0xFFD97706),
                            ),

                            const SizedBox(width: 12),

                            Expanded(
                              child: Text(
                                '${registrosPendientes.length} '
                                '${registrosPendientes.length == 1 ? 'registro pendiente' : 'registros pendientes'} '
                                'de sincronización.',
                                style: const TextStyle(
                                  color: Color(0xFF92400E),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: sincronizando ? null : _sincronizarAhora,
                          icon: sincronizando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Icon(Icons.sync),
                          label: Text(
                            sincronizando
                                ? 'Sincronizando...'
                                : 'Sincronizar ahora',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFE5E7EB),
                            disabledForegroundColor: const Color(0xFF6B7280),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 22),

                      const Text(
                        'Por sincronizar',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),

                      const SizedBox(height: 14),

                      ...registrosPendientes.map(
                        (registro) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),

                          child: _RegistroPendiente(registro: registro),
                        ),
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        'Desliza hacia abajo o usa el botón de actualizar '
                        'para volver a leer el estado guardado en el teléfono.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
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
// TARJETA PARA REGISTRO PENDIENTE REAL
// -----------------------------------------------------------------

class _RegistroPendiente extends StatelessWidget {
  final Map<String, dynamic> registro;

  const _RegistroPendiente({required this.registro});

  Map<String, dynamic> get payload {
    final dynamic raw = registro['payload'];

    if (raw is! Map) {
      return <String, dynamic>{};
    }

    return Map<String, dynamic>.from(raw);
  }

  List<Map<String, dynamic>> get evidencias {
    final dynamic raw = registro['evidencias'];

    if (raw is! List) {
      return <Map<String, dynamic>>[];
    }

    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String get lugar {
    final String valor = (payload['lugar'] ?? '').toString().trim();

    if (valor.isNotEmpty) {
      return valor;
    }

    final String idEspacio = (payload['id_espacio'] ?? '').toString().trim();

    if (idEspacio.isNotEmpty) {
      return 'Espacio $idEspacio';
    }

    return 'Registro de aseo';
  }

  DateTime? get fechaReferencia {
    final List<dynamic> candidatos = <dynamic>[
      payload['fecha_hora_fin'],
      payload['fecha_registro_final'],
      registro['fecha_creacion'],
    ];

    for (final dynamic candidato in candidatos) {
      if (candidato == null) {
        continue;
      }

      final DateTime? fecha = DateTime.tryParse(candidato.toString());

      if (fecha != null) {
        return fecha.toLocal();
      }
    }

    return null;
  }

  String get fecha {
    final DateTime? valor = fechaReferencia;

    if (valor == null) {
      return '—';
    }

    final String dia = valor.day.toString().padLeft(2, '0');

    final String mes = valor.month.toString().padLeft(2, '0');

    return '$dia/$mes/${valor.year}';
  }

  String get hora {
    final DateTime? valor = fechaReferencia;

    if (valor == null) {
      return '—';
    }

    final String hora = valor.hour.toString().padLeft(2, '0');

    final String minuto = valor.minute.toString().padLeft(2, '0');

    return '$hora:$minuto';
  }

  String get estadoSincronizacion {
    final String estado = (registro['estado'] ?? 'Pendiente').toString().trim();

    if (estado.isEmpty) {
      return 'Pendiente';
    }

    return estado;
  }

  String get estadoAseo {
    return (payload['estado_aseo'] ?? '').toString().trim();
  }

  int get intentos {
    final dynamic valor = registro['intentos'];

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String get ultimoError {
    return (registro['ultimo_error'] ?? '').toString().trim();
  }

  Color get colorEstado {
    switch (estadoSincronizacion) {
      case 'Error':
        return const Color(0xFFDC2626);

      case 'Sincronizando':
        return const Color(0xFF2563EB);

      default:
        return const Color(0xFFD97706);
    }
  }

  Color get fondoEstado {
    switch (estadoSincronizacion) {
      case 'Error':
        return const Color(0xFFFEF2F2);

      case 'Sincronizando':
        return const Color(0xFFEFF6FF);

      default:
        return const Color(0xFFFFFBEB);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                estadoSincronizacion == 'Error'
                    ? Icons.error_outline
                    : Icons.cloud_upload_outlined,
                color: colorEstado,
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  lugar,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _DatoPendiente(titulo: 'Fecha', valor: fecha),
              ),

              Expanded(
                child: _DatoPendiente(titulo: 'Hora', valor: hora),
              ),
            ],
          ),

          if (estadoAseo.isNotEmpty || evidencias.isNotEmpty) ...[
            const SizedBox(height: 14),

            Row(
              children: [
                if (estadoAseo.isNotEmpty)
                  Expanded(
                    child: _DatoPendiente(
                      titulo: 'Resultado',
                      valor: estadoAseo,
                    ),
                  ),

                if (evidencias.isNotEmpty)
                  Expanded(
                    child: _DatoPendiente(
                      titulo: 'Fotografías',
                      valor: '${evidencias.length}',
                    ),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 14),

          const Divider(),

          const SizedBox(height: 10),

          Row(
            children: [
              const Expanded(
                child: Text(
                  'Estado de sincronización',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
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
                  estadoSincronizacion,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorEstado,
                  ),
                ),
              ),
            ],
          ),

          if (intentos > 0) ...[
            const SizedBox(height: 10),

            Text(
              'Intentos realizados: $intentos',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],

          if (ultimoError.isNotEmpty) ...[
            const SizedBox(height: 10),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),

              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
              ),

              child: Text(
                ultimoError,
                style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------
// DATO PEQUEÑO DEL REGISTRO
// -----------------------------------------------------------------

class _DatoPendiente extends StatelessWidget {
  final String titulo;
  final String valor;

  const _DatoPendiente({required this.titulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Text(
          titulo,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),

        const SizedBox(height: 4),

        Text(
          valor,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }
}
