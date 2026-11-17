import 'dart:async';
import 'dart:math' as math;

import '../remote/remote_backend.dart';
import '../storage/local_storage.dart';
import 'labor_context.dart';

class LaborOperacionResultado {
  final LaborContext labor;
  final bool modoOffline;

  const LaborOperacionResultado({
    required this.labor,
    required this.modoOffline,
  });

  int? get idRegistroRemoto => labor.idRegistroRemoto;

  String get idLocal => labor.idLocal;
}

class LaborOperacionService {
  final LocalStorage localStorage;
  final RemoteBackend remoteBackend;

  /// Tiempo máximo para considerar que el backend remoto
  /// no está disponible y continuar con la copia local.
  final Duration timeoutRemoto;

  const LaborOperacionService({
    required this.localStorage,
    required this.remoteBackend,
    this.timeoutRemoto = const Duration(seconds: 25),
  });

  // =============================================================
  // RECONCILIAR CIERRE EXCEPCIONAL CON EL SERVIDOR
  // =============================================================
  // Nunca elimina una labor por estar simplemente "cerrada" técnicamente.
  // Solo la libera cuando la solicitud correspondiente fue APROBADA
  // y la misma labor tiene fecha de término remota.
  // En caso de error o falta de conexión, conserva intacto Hive.

  Future<String> reconciliarCierreExcepcional({
    required String idUsuario,
  }) async {
    final Map<String, dynamic>? guardada = localStorage.obtenerLaborEnCurso(
      idUsuario,
    );

    if (guardada == null) return 'sin_labor_local';
    if (guardada['id_usuario']?.toString() != idUsuario) {
      return 'sin_confirmacion';
    }
    if ((guardada['estado_local'] ?? '').toString() != 'En curso') {
      return 'no_aplica';
    }

    final int? idRemoto = _aInt(guardada['id_registro_remoto']);
    if (idRemoto == null) return 'sin_registro_remoto';

    try {
      final Map<String, dynamic> consulta = await remoteBackend
          .consultarEstadoCierreExcepcional(idRegistroRemoto: idRemoto)
          .timeout(timeoutRemoto);

      final String estado = (consulta['estado'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (consulta['ok'] != true) return 'sin_confirmacion';

      if (estado == 'aprobada' && consulta['cerrada'] == true) {
        // Puede haber cambiado la labor mientras respondía el servidor.
        // Nunca borrar una labor distinta (ni de otro usuario).
        final Map<String, dynamic>? actual = localStorage.obtenerLaborEnCurso(
          idUsuario,
        );
        if (actual != null &&
            actual['id_usuario']?.toString() == idUsuario &&
            _aInt(actual['id_registro_remoto']) == idRemoto &&
            actual['id_local']?.toString() ==
                guardada['id_local']?.toString() &&
            (actual['estado_local'] ?? '').toString() == 'En curso') {
          await localStorage.eliminarLaborEnCurso(idUsuario);
          return 'aprobada';
        }
        return 'cambio_local';
      }
      if (estado == 'pendiente' || estado == 'rechazada') return estado;
      return 'sin_confirmacion';
    } on TimeoutException {
      return 'sin_confirmacion';
    } catch (_) {
      // No liberar la labor por una falla de red, permisos o RPC ausente.
      return 'sin_confirmacion';
    }
  }

  // =============================================================
  // INICIAR LABOR
  // =============================================================

  Future<LaborOperacionResultado> iniciarLabor({
    required String idUsuario,
    required int idEspacio,
    required String uidNfc,
    required double latitudInicio,
    required double longitudInicio,
    required String lugar,
    required String nombreAuxiliar,
    bool esCobertura = false,
    double? radioLatitudCobertura,
    double? radioLongitudCobertura,
    double? radioMetrosCobertura,
    int? idNfcCobertura,
  }) async {
    final Map<String, dynamic>? laborExistente = localStorage
        .obtenerLaborEnCurso(idUsuario);

    if (laborExistente != null) {
      // Revalidamos el cierre excepcional ANTES de bloquear por Hive.
      final String estado = await reconciliarCierreExcepcional(
        idUsuario: idUsuario,
      );

      // Solo una aprobación remota comprobada libera el registro local.
      if (localStorage.obtenerLaborEnCurso(idUsuario) != null) {
        if (estado == 'pendiente') {
          throw StateError(
            'Tu cierre excepcional todavía está pendiente de aprobación. '
            'No puedes comenzar otra labor hasta que se resuelva.',
          );
        }
        if (estado == 'rechazada') {
          throw StateError(
            'Tu solicitud de cierre excepcional fue rechazada. '
            'Debes continuar o finalizar la labor anterior.',
          );
        }
        throw StateError(
          'Ya existe una labor en curso en este dispositivo. '
          'Debes finalizarla antes de iniciar otra. '
          'Si fue cerrada excepcionalmente, revisa la conexión '
          'para confirmar la aprobación.',
        );
      }
    }

    final String uidNormalizado = _normalizarUid(uidNfc);

    // -----------------------------------------------------------
    // PRIMERO INTENTAMOS BACKEND REMOTO
    // -----------------------------------------------------------

    try {
      final Future<Map<String, dynamic>> inicioRemoto = esCobertura
          ? remoteBackend.iniciarLaborCobertura(
              idEspacio: idEspacio,
              uidNfc: uidNormalizado,
              latitudInicio: latitudInicio,
              longitudInicio: longitudInicio,
            )
          : remoteBackend.iniciarLabor(
              idEspacio: idEspacio,
              uidNfc: uidNormalizado,
              latitudInicio: latitudInicio,
              longitudInicio: longitudInicio,
            );
      final Map<String, dynamic> remoto = await inicioRemoto.timeout(
        timeoutRemoto,
      );

      final int? idRemoto = _aInt(remoto['id_registro_aseo']);

      if (idRemoto == null) {
        throw const RemoteUnavailableException(
          'El backend no entregó el identificador del registro.',
        );
      }

      final DateTime horaInicio =
          _aFecha(remoto['fecha_hora_inicio']) ?? DateTime.now();

      final Map<String, dynamic>? datosCache = esCobertura
          ? <String, dynamic>{
              'radio_latitud': radioLatitudCobertura,
              'radio_longitud': radioLongitudCobertura,
              'radio_metros': radioMetrosCobertura,
              'id_nfc': idNfcCobertura,
            }
          : _obtenerDatosCacheParaLabor(
              idUsuario: idUsuario,
              idEspacio: idEspacio,
              uidNfc: uidNormalizado,
            );

      final Map<String, dynamic> labor = _crearLaborLocal(
        idUsuario: idUsuario,
        idEspacio: idEspacio,
        uidNfc: uidNormalizado,
        latitudInicio: latitudInicio,
        longitudInicio: longitudInicio,
        lugar: lugar,
        nombreAuxiliar: nombreAuxiliar,
        horaInicio: horaInicio,
        idRegistroRemoto: idRemoto,
        origen: 'online',
        requiereSincronizacion: false,
        cacheValidacion: datosCache,
        esCobertura: esCobertura,
      );

      await localStorage.guardarLaborEnCurso(
        idUsuario: idUsuario,
        labor: labor,
      );

      return LaborOperacionResultado(
        labor: LaborContext.fromMap(labor),
        modoOffline: false,
      );
    } on RemoteRejectedException {
      // Si el servidor respondió y rechazó por una regla
      // de negocio, NO debemos saltarnos esa regla usando
      // la caché local.
      rethrow;
    } on TimeoutException {
      // El servidor puede haber iniciado la labor aunque la respuesta
      // haya demorado. Nunca crear otro inicio local sin confirmarlo:
      // se podrían producir dos registros para la misma tarea.
      throw const RemoteUnavailableException(
        'El servidor no confirmó el inicio a tiempo. No se creó otra '
        'labor offline para evitar duplicaciones. Revisa la conexión '
        'y el estado del registro antes de volver a intentar.',
      );
    } on RemoteUnavailableException {
      if (esCobertura) rethrow;
      // Las labores normales mantienen su modo offline.
    }

    // -----------------------------------------------------------
    // MODO OFFLINE
    // -----------------------------------------------------------

    final Map<String, dynamic> validacion = _validarInicioOffline(
      idUsuario: idUsuario,
      idEspacio: idEspacio,
      uidNfc: uidNormalizado,
      latitud: latitudInicio,
      longitud: longitudInicio,
    );

    final DateTime ahora = DateTime.now();

    final Map<String, dynamic> labor = _crearLaborLocal(
      idUsuario: idUsuario,
      idEspacio: idEspacio,
      uidNfc: uidNormalizado,
      latitudInicio: latitudInicio,
      longitudInicio: longitudInicio,
      lugar: lugar,
      nombreAuxiliar: nombreAuxiliar,
      horaInicio: ahora,
      idRegistroRemoto: null,
      origen: 'offline',
      requiereSincronizacion: true,
      cacheValidacion: validacion,
    );

    await localStorage.guardarLaborEnCurso(idUsuario: idUsuario, labor: labor);

    return LaborOperacionResultado(
      labor: LaborContext.fromMap(labor),
      modoOffline: true,
    );
  }

  // =============================================================
  // FINALIZAR LABOR
  // =============================================================

  Future<LaborOperacionResultado> finalizarLabor({
    required String idUsuario,
    required String uidNfc,
    required double latitudFin,
    required double longitudFin,
  }) async {
    final Map<String, dynamic>? actual = localStorage.obtenerLaborEnCurso(
      idUsuario,
    );

    if (actual == null) {
      throw StateError('No existe una labor en curso.');
    }

    if ((actual['estado_local'] ?? '').toString() != 'En curso') {
      throw StateError('La labor ya fue finalizada.');
    }

    final String uidNormalizado = _normalizarUid(uidNfc);

    final int? idRemoto = _aInt(actual['id_registro_remoto']);

    // -----------------------------------------------------------
    // SI EXISTE REGISTRO REMOTO, INTENTAMOS PRIMERO EL SERVIDOR
    // -----------------------------------------------------------

    if (idRemoto != null) {
      try {
        final Map<String, dynamic> remoto = await remoteBackend
            .finalizarLabor(
              idRegistroRemoto: idRemoto,
              uidNfc: uidNormalizado,
              latitudFin: latitudFin,
              longitudFin: longitudFin,
            )
            .timeout(timeoutRemoto);

        final DateTime horaFin =
            _aFecha(remoto['fecha_hora_fin']) ?? DateTime.now();

        final Map<String, dynamic> labor = {
          ...actual,
          'fecha_hora_fin': horaFin.toUtc().toIso8601String(),
          'latitud_fin': latitudFin,
          'longitud_fin': longitudFin,
          'estado_local': 'Finalizada pendiente de detalle',
          'requiere_sincronizacion': false,
          'termino_registrado_online': true,
        };

        await localStorage.guardarLaborEnCurso(
          idUsuario: idUsuario,
          labor: labor,
        );

        return LaborOperacionResultado(
          labor: LaborContext.fromMap(labor),
          modoOffline: false,
        );
      } on RemoteRejectedException {
        // Si el servidor respondió y rechazó el término,
        // respetamos la regla de negocio.
        rethrow;
      } on TimeoutException {
        // Continuamos con validación local.
      } on RemoteUnavailableException {
        // Continuamos con validación local.
      }
    }

    // -----------------------------------------------------------
    // MODO OFFLINE / SERVIDOR NO DISPONIBLE
    // -----------------------------------------------------------

    _validarTerminoOfflineBase(
      labor: actual,
      uidNfc: uidNormalizado,
      latitud: latitudFin,
      longitud: longitudFin,
    );

    final DateTime horaFin = DateTime.now();

    final Map<String, dynamic> labor = {
      ...actual,
      'fecha_hora_fin': horaFin.toUtc().toIso8601String(),
      'latitud_fin': latitudFin,
      'longitud_fin': longitudFin,
      'estado_local': 'Finalizada pendiente de detalle',
      'requiere_sincronizacion': true,
      'termino_registrado_online': false,
    };

    await localStorage.guardarLaborEnCurso(idUsuario: idUsuario, labor: labor);

    return LaborOperacionResultado(
      labor: LaborContext.fromMap(labor),
      modoOffline: true,
    );
  }

  Map<String, dynamic>? _obtenerDatosCacheParaLabor({
    required String idUsuario,
    required int idEspacio,
    required String uidNfc,
  }) {
    final Map<String, dynamic>? cache = localStorage.obtenerCacheOperacional(
      idUsuario,
    );

    if (cache == null) {
      return null;
    }

    final Map<String, dynamic>? espacio = _buscarPorId(
      _listaMap(cache['espacios']),
      'id_espacio',
      idEspacio,
    );

    if (espacio == null) {
      return null;
    }

    Map<String, dynamic>? nfc;

    for (final fila in _listaMap(cache['nfc_vigentes'])) {
      if (_aInt(fila['id_espacio']) == idEspacio &&
          _normalizarUid((fila['uid_nfc'] ?? '').toString()) == uidNfc) {
        nfc = fila;
        break;
      }
    }

    final double? latitudObjetivo = _aDouble(espacio['radio_latitud']);

    final double? longitudObjetivo = _aDouble(espacio['radio_longitud']);

    final double? radioMetros = _aDouble(espacio['radio_metros']);

    if (latitudObjetivo == null ||
        longitudObjetivo == null ||
        radioMetros == null ||
        radioMetros <= 0) {
      return null;
    }

    return {
      'fecha_cache': cache['fecha_cache'],
      'id_nfc': nfc?['id_nfc'],
      'id_estado_nfc': nfc?['id_estado_nfc'],
      'radio_latitud': latitudObjetivo,
      'radio_longitud': longitudObjetivo,
      'radio_metros': radioMetros,
    };
  }

  // =============================================================
  // VALIDACIÓN OFFLINE DE INICIO
  // =============================================================

  Map<String, dynamic> _validarInicioOffline({
    required String idUsuario,
    required int idEspacio,
    required String uidNfc,
    required double latitud,
    required double longitud,
  }) {
    final Map<String, dynamic>? cache = localStorage.obtenerCacheOperacional(
      idUsuario,
    );

    if (cache == null) {
      throw StateError(
        'No existe información local para trabajar sin conexión. Conéctate a Internet al menos una vez para actualizar tus sectores.',
      );
    }

    final List<Map<String, dynamic>> asignaciones = _listaMap(
      cache['asignaciones_espacios'],
    );

    final bool asignado = asignaciones.any(
      (fila) => _aInt(fila['id_espacio']) == idEspacio,
    );

    if (!asignado) {
      throw StateError(
        'El espacio no se encuentra en tus asignaciones locales vigentes.',
      );
    }

    final Map<String, dynamic>? espacio = _buscarPorId(
      _listaMap(cache['espacios']),
      'id_espacio',
      idEspacio,
    );

    if (espacio == null || espacio['activo'] != true) {
      throw StateError('El espacio no está disponible en la caché local.');
    }

    final List<Map<String, dynamic>> nfcs = _listaMap(cache['nfc_vigentes']);

    Map<String, dynamic>? nfc;

    for (final fila in nfcs) {
      if (_aInt(fila['id_espacio']) == idEspacio &&
          _normalizarUid((fila['uid_nfc'] ?? '').toString()) == uidNfc) {
        nfc = fila;
        break;
      }
    }

    if (nfc == null) {
      throw StateError('El NFC leído no corresponde al espacio asignado.');
    }

    final int? idEstadoNfc = _aInt(nfc['id_estado_nfc']);

    final Map<String, dynamic>? estadoNfc = _buscarPorId(
      _listaMap(cache['estados_nfc']),
      'id_estado_nfc',
      idEstadoNfc,
    );

    final String nombreEstado = (estadoNfc?['nombre_estado'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (nombreEstado != 'operativo') {
      throw StateError(
        'El NFC no se encuentra operativo según la última información sincronizada.',
      );
    }

    final double? latitudObjetivo = _aDouble(espacio['radio_latitud']);

    final double? longitudObjetivo = _aDouble(espacio['radio_longitud']);

    final double? radioMetros = _aDouble(espacio['radio_metros']);

    if (latitudObjetivo == null ||
        longitudObjetivo == null ||
        radioMetros == null ||
        radioMetros <= 0) {
      throw StateError(
        'El espacio no posee una configuración GPS válida en la caché local.',
      );
    }

    final double distancia = _distanciaMetros(
      latitud,
      longitud,
      latitudObjetivo,
      longitudObjetivo,
    );

    if (distancia > radioMetros) {
      throw StateError(
        'Tu ubicación está fuera del radio permitido para este espacio.',
      );
    }

    return {
      'fecha_cache': cache['fecha_cache'],
      'id_nfc': nfc['id_nfc'],
      'id_estado_nfc': nfc['id_estado_nfc'],
      'radio_latitud': latitudObjetivo,
      'radio_longitud': longitudObjetivo,
      'radio_metros': radioMetros,
      'distancia_inicio_metros': distancia,
    };
  }

  // =============================================================
  // VALIDACIÓN OFFLINE DE TÉRMINO
  // =============================================================

  void _validarTerminoOfflineBase({
    required Map<String, dynamic> labor,
    required String uidNfc,
    required double latitud,
    required double longitud,
  }) {
    final String uidInicio = _normalizarUid(
      (labor['uid_nfc_inicio'] ?? '').toString(),
    );

    if (uidInicio.isEmpty || uidInicio != uidNfc) {
      throw StateError(
        'Debes finalizar la labor utilizando el mismo NFC con el que fue iniciada.',
      );
    }

    final double? latitudObjetivo = _aDouble(labor['radio_latitud']);

    final double? longitudObjetivo = _aDouble(labor['radio_longitud']);

    final double? radioMetros = _aDouble(labor['radio_metros']);

    if (latitudObjetivo == null ||
        longitudObjetivo == null ||
        radioMetros == null ||
        radioMetros <= 0) {
      throw StateError('La labor no posee una configuración GPS local válida.');
    }

    final double distancia = _distanciaMetros(
      latitud,
      longitud,
      latitudObjetivo,
      longitudObjetivo,
    );

    if (distancia > radioMetros) {
      throw StateError(
        'Tu ubicación está fuera del radio permitido para finalizar esta labor.',
      );
    }
  }

  // =============================================================
  // CREACIÓN DEL REGISTRO LOCAL
  // =============================================================

  Map<String, dynamic> _crearLaborLocal({
    required String idUsuario,
    required int idEspacio,
    required String uidNfc,
    required double latitudInicio,
    required double longitudInicio,
    required String lugar,
    required String nombreAuxiliar,
    required DateTime horaInicio,
    required int? idRegistroRemoto,
    required String origen,
    required bool requiereSincronizacion,
    Map<String, dynamic>? cacheValidacion,
    bool esCobertura = false,
  }) {
    final String idLocal =
        '${idUsuario}_${DateTime.now().microsecondsSinceEpoch}';

    return {
      'id_local': idLocal,
      'id_usuario': idUsuario,
      'id_espacio': idEspacio,
      'id_registro_remoto': idRegistroRemoto,
      'es_cobertura': esCobertura,
      'origen': origen,
      'estado_local': 'En curso',
      'requiere_sincronizacion': requiereSincronizacion,
      'uid_nfc_inicio': uidNfc,
      'id_nfc_inicio': cacheValidacion?['id_nfc'],
      'fecha_hora_inicio': horaInicio.toUtc().toIso8601String(),
      'fecha_hora_fin': null,
      'latitud_inicio': latitudInicio,
      'longitud_inicio': longitudInicio,
      'latitud_fin': null,
      'longitud_fin': null,
      'lugar': lugar,
      'nombre_auxiliar': nombreAuxiliar,
      'fecha_cache_validacion': cacheValidacion?['fecha_cache'],
      'radio_latitud': cacheValidacion?['radio_latitud'],
      'radio_longitud': cacheValidacion?['radio_longitud'],
      'radio_metros': cacheValidacion?['radio_metros'],
      'distancia_inicio_metros': cacheValidacion?['distancia_inicio_metros'],
    };
  }

  // =============================================================
  // UTILIDADES
  // =============================================================

  String _normalizarUid(String valor) {
    return valor
        .trim()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .toUpperCase();
  }

  int? _aInt(dynamic valor) {
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

  double? _aDouble(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is double) {
      return valor;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor.toString());
  }

  DateTime? _aFecha(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is DateTime) {
      return valor;
    }

    return DateTime.tryParse(valor.toString());
  }

  List<Map<String, dynamic>> _listaMap(dynamic valor) {
    if (valor is! List) {
      return <Map<String, dynamic>>[];
    }

    return valor
        .whereType<Map>()
        .map((fila) => Map<String, dynamic>.from(fila))
        .toList();
  }

  Map<String, dynamic>? _buscarPorId(
    List<Map<String, dynamic>> lista,
    String campo,
    int? id,
  ) {
    if (id == null) {
      return null;
    }

    for (final fila in lista) {
      if (_aInt(fila[campo]) == id) {
        return fila;
      }
    }

    return null;
  }

  double _distanciaMetros(double lat1, double lon1, double lat2, double lon2) {
    const double radioTierra = 6371000;

    double rad(double grados) => grados * math.pi / 180;

    final double dLat = rad(lat2 - lat1);

    final double dLon = rad(lon2 - lon1);

    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return radioTierra * c;
  }
}
