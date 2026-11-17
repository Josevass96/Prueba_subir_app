import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;

import '../storage/local_storage.dart';

class RegistroFinalFallbackService {
  final LocalStorage localStorage;
  final SupabaseClient supabase;

  const RegistroFinalFallbackService({
    required this.localStorage,
    required this.supabase,
  });

  /// Comprueba si el backend realmente responde.
  ///
  /// No usamos solo "hay Wi-Fi / datos móviles", porque eso no
  /// garantiza que Supabase sea alcanzable.
  Future<bool> backendDisponible() async {
    try {
      await supabase
          .from('estado_aseo')
          .select('id_estado_aseo')
          .limit(1)
          .timeout(const Duration(seconds: 15));

      return true;
    } on TimeoutException {
      debugPrint('REGISERV: Supabase no respondió al comprobar conexión.');
      return false;
    } on PostgrestException catch (error) {
      // PGRST000-003 significa que PostgREST no consiguió atender la
      // petición / establecer conexión con la base de datos.
      // No debemos marcar el backend como disponible en esos casos.
      const erroresInfraestructura = <String>{
        'PGRST000',
        'PGRST001',
        'PGRST002',
        'PGRST003',
      };
      if (erroresInfraestructura.contains((error.code ?? '').toUpperCase())) {
        debugPrint('REGISERV: backend inaccesible: ${error.message}');
        return false;
      }
      // Un error de RLS o de consulta confirma respuesta del servidor,
      // aunque la sincronización aún podría fallar por permisos.
      debugPrint('REGISERV: Supabase respondió con error: ${error.message}');
      return true;
    } on AuthException catch (error) {
      debugPrint('REGISERV: error de autenticación: ${error.message}');
      return true;
    } catch (error) {
      debugPrint('REGISERV: no fue posible conectar al backend: $error');
      return false;
    }
  }

  /// Guarda el cierre final de una labor que YA posee un
  /// id_registro_aseo remoto, pero cuyo envío final no pudo
  /// completarse por falta de conexión/backend.
  Future<String> guardarPendiente({
    required String idUsuario,
    required int idRegistroAseo,
    required String estadoAseo,
    required DateTime horaInicio,
    required DateTime horaTermino,
    required String lugar,
    required String nombreAuxiliar,
    String? comentario,
    String? tipoObservacion,
    String? detalleObservacion,
    List<Map<String, dynamic>> evidenciasPendientes =
        const <Map<String, dynamic>>[],
  }) async {
    final Map<String, dynamic>? laborLocal = localStorage.obtenerLaborEnCurso(
      idUsuario,
    );

    final Map<String, dynamic> payload = <String, dynamic>{
      ...?laborLocal,

      'id_registro_remoto': idRegistroAseo,
      'origen': 'online_fallback',
      'estado_local': 'Finalizada pendiente de sincronización',
      'requiere_sincronizacion': true,

      'estado_aseo': estadoAseo,
      'comentario': comentario,
      'tipo_observacion': tipoObservacion,
      'detalle_observacion': detalleObservacion,

      'fecha_hora_inicio': horaInicio.toUtc().toIso8601String(),
      'fecha_hora_fin': horaTermino.toUtc().toIso8601String(),

      'lugar': lugar,
      'nombre_auxiliar': nombreAuxiliar,

      'estado_sincronizacion': 'Pendiente',
      'fecha_registro_final': DateTime.now().toUtc().toIso8601String(),
    };

    final String idPendiente = await localStorage.agregarPendiente(
      idUsuario: idUsuario,
      tipo: 'completar_registro_remoto',
      payload: payload,
      evidencias: evidenciasPendientes,
    );

    // La labor ya quedó cerrada y protegida en la cola.
    // Quitamos únicamente la marca "labor en curso".
    await localStorage.eliminarLaborEnCurso(idUsuario);

    return idPendiente;
  }
}
