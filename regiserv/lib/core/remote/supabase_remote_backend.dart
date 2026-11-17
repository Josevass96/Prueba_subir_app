import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'remote_backend.dart';

class SupabaseRemoteBackend implements RemoteBackend {
  final SupabaseClient supabase;

  SupabaseRemoteBackend(this.supabase);

  @override
  String get nombreProveedor => 'Supabase';

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

  List<Map<String, dynamic>> _aListaMap(dynamic respuesta) {
    if (respuesta is! List) {
      return <Map<String, dynamic>>[];
    }

    return respuesta
        .whereType<Map>()
        .map((fila) => Map<String, dynamic>.from(fila))
        .toList();
  }

  Never _lanzarErrorRemoto(Object error) {
    if (error is RemoteRejectedException ||
        error is RemoteUnavailableException) {
      throw error;
    }

    if (error is PostgrestException) {
      final String codigo = (error.code ?? '').toUpperCase();

      if (codigo == 'PGRST000' ||
          codigo == 'PGRST001' ||
          codigo == 'PGRST002' ||
          codigo == 'PGRST003') {
        throw RemoteUnavailableException(error.message);
      }

      throw RemoteRejectedException(error.message);
    }

    if (error is AuthException) {
      throw RemoteRejectedException(error.message);
    }

    throw RemoteUnavailableException(error.toString());
  }

  Map<String, dynamic> _aMapaRespuesta(
    dynamic respuesta, {
    required String operacion,
  }) {
    if (respuesta is! Map) {
      throw RemoteRejectedException(
        'El servidor entregó una respuesta inesperada al $operacion. '
        'La operación requiere revisión y no debe registrarse como offline.',
      );
    }

    return Map<String, dynamic>.from(respuesta);
  }

  // ============================================================
  // CACHE OPERACIONAL
  // ============================================================

  @override
  Future<Map<String, dynamic>> obtenerCacheOperacional({
    required String idUsuario,
  }) async {
    final User? usuarioAuth = supabase.auth.currentUser;

    if (usuarioAuth == null) {
      throw StateError('No existe una sesión autenticada.');
    }

    if (usuarioAuth.id != idUsuario) {
      throw StateError(
        'La sesión autenticada no corresponde al usuario solicitado.',
      );
    }

    final dynamic espaciosAsignadosRaw = await supabase
        .from('espacio_trabajador')
        .select(
          'id_espacio, '
          'fecha_ini, '
          'fecha_ter, '
          'comentario',
        )
        .eq('id_usuario', idUsuario)
        .isFilter('fecha_ter', null);

    final List<Map<String, dynamic>> asignacionesEspacios = _aListaMap(
      espaciosAsignadosRaw,
    );

    final dynamic pisosAsignadosRaw = await supabase
        .from('piso_trabajador')
        .select(
          'id_piso, '
          'fecha_ini, '
          'fecha_fin, '
          'comentario',
        )
        .eq('id_usuario', idUsuario)
        .isFilter('fecha_fin', null);

    final List<Map<String, dynamic>> asignacionesPisos = _aListaMap(
      pisosAsignadosRaw,
    );

    final Set<int> idsEspacios = <int>{};

    for (final asignacion in asignacionesEspacios) {
      final int? id = _aInt(asignacion['id_espacio']);

      if (id != null) {
        idsEspacios.add(id);
      }
    }

    List<Map<String, dynamic>> espacios = <Map<String, dynamic>>[];

    if (idsEspacios.isNotEmpty) {
      final dynamic espaciosRaw = await supabase
          .from('espacio')
          .select(
            'id_espacio, '
            'id_piso, '
            'id_tipo_espacio, '
            'codigo, '
            'nombre, '
            'radio_latitud, '
            'radio_longitud, '
            'radio_metros, '
            'activo',
          )
          .inFilter('id_espacio', idsEspacios.toList());

      espacios = _aListaMap(espaciosRaw);
    }

    final Set<int> idsPisos = <int>{};

    for (final asignacion in asignacionesPisos) {
      final int? id = _aInt(asignacion['id_piso']);

      if (id != null) {
        idsPisos.add(id);
      }
    }

    for (final espacio in espacios) {
      final int? id = _aInt(espacio['id_piso']);

      if (id != null) {
        idsPisos.add(id);
      }
    }

    List<Map<String, dynamic>> pisos = <Map<String, dynamic>>[];

    if (idsPisos.isNotEmpty) {
      final dynamic pisosRaw = await supabase
          .from('piso_nivel')
          .select(
            'id_piso, '
            'id_edificio, '
            'numero_nivel, '
            'activo',
          )
          .inFilter('id_piso', idsPisos.toList());

      pisos = _aListaMap(pisosRaw);
    }

    final Set<int> idsEdificios = <int>{};

    for (final piso in pisos) {
      final int? id = _aInt(piso['id_edificio']);

      if (id != null) {
        idsEdificios.add(id);
      }
    }

    List<Map<String, dynamic>> edificios = <Map<String, dynamic>>[];

    if (idsEdificios.isNotEmpty) {
      final dynamic edificiosRaw = await supabase
          .from('edificio')
          .select(
            'id_edificio, '
            'id_sede, '
            'codigo, '
            'nombre, '
            'activo',
          )
          .inFilter('id_edificio', idsEdificios.toList());

      edificios = _aListaMap(edificiosRaw);
    }

    final Set<int> idsTipos = <int>{};

    for (final espacio in espacios) {
      final int? id = _aInt(espacio['id_tipo_espacio']);

      if (id != null) {
        idsTipos.add(id);
      }
    }

    List<Map<String, dynamic>> tiposEspacio = <Map<String, dynamic>>[];

    if (idsTipos.isNotEmpty) {
      final dynamic tiposRaw = await supabase
          .from('tipo_espacio')
          .select(
            'id_tipo_espacio, '
            'nombre, '
            'activo',
          )
          .inFilter('id_tipo_espacio', idsTipos.toList());

      tiposEspacio = _aListaMap(tiposRaw);
    }

    final dynamic estadosNfcRaw = await supabase
        .from('estado_nfc')
        .select(
          'id_estado_nfc, '
          'nombre_estado, '
          'activo, '
          'comentario',
        );

    final List<Map<String, dynamic>> estadosNfc = _aListaMap(estadosNfcRaw);

    List<Map<String, dynamic>> nfcVigentes = <Map<String, dynamic>>[];

    if (idsEspacios.isNotEmpty) {
      final dynamic nfcRaw = await supabase
          .from('nfc')
          .select(
            'id_nfc, '
            'id_espacio, '
            'id_estado_nfc, '
            'uid_nfc, '
            'fecha_instalacion, '
            'fecha_retiro, '
            'latitud, '
            'longitud, '
            'comentario',
          )
          .inFilter('id_espacio', idsEspacios.toList())
          .isFilter('fecha_retiro', null);

      nfcVigentes = _aListaMap(nfcRaw);
    }

    final dynamic estadosAseoRaw = await supabase
        .from('estado_aseo')
        .select(
          'id_estado_aseo, '
          'nombre, '
          'descripcion',
        );

    final List<Map<String, dynamic>> estadosAseo = _aListaMap(estadosAseoRaw);

    final dynamic tiposObservacionRaw = await supabase
        .from('tipo_observacion')
        .select(
          'id_tipo_observacion, '
          'nombre, '
          'descripcion, '
          'activo, '
          'deriva_mantencion',
        )
        .eq('activo', true);

    final List<Map<String, dynamic>> tiposObservacion = _aListaMap(
      tiposObservacionRaw,
    );

    return {
      'version_cache': 1,
      'id_usuario': idUsuario,
      'proveedor_remoto': nombreProveedor,
      'asignaciones_espacios': asignacionesEspacios,
      'asignaciones_pisos': asignacionesPisos,
      'espacios': espacios,
      'pisos': pisos,
      'edificios': edificios,
      'tipos_espacio': tiposEspacio,
      'estados_nfc': estadosNfc,
      'nfc_vigentes': nfcVigentes,
      'estados_aseo': estadosAseo,
      'tipos_observacion': tiposObservacion,
    };
  }

  // ============================================================
  // INICIAR LABOR ONLINE
  // ============================================================

  @override
  Future<Map<String, dynamic>> iniciarLabor({
    required int idEspacio,
    required String uidNfc,
    required double latitudInicio,
    required double longitudInicio,
  }) async {
    try {
      final dynamic respuesta = await supabase.rpc(
        'iniciar_labor_aseo',
        params: {
          'p_id_espacio': idEspacio,
          'p_uid_nfc': uidNfc,
          'p_latitud_inicio': latitudInicio,
          'p_longitud_inicio': longitudInicio,
        },
      );

      // iniciar_labor_aseo retorna TABLE en Supabase.
      // PostgREST suele entregarla como lista de una sola fila.
      final dynamic fila = respuesta is List && respuesta.isNotEmpty
          ? respuesta.first
          : respuesta;
      final Map<String, dynamic> data = _aMapaRespuesta(
        fila,
        operacion: 'iniciar la labor',
      );

      if (data['ok'] == false) {
        throw RemoteRejectedException(
          (data['mensaje'] ?? 'No fue posible iniciar la labor.').toString(),
        );
      }
      if (data['id_registro_aseo'] == null) {
        throw const RemoteRejectedException(
          'El servidor no devolvió el registro de la labor.',
        );
      }

      return <String, dynamic>{'ok': true, ...data};
    } catch (error) {
      _lanzarErrorRemoto(error);
    }
  }

  // ============================================================
  // INICIAR COBERTURA (solo online, autorizada en Supabase)
  // ============================================================

  @override
  Future<Map<String, dynamic>> iniciarLaborCobertura({
    required int idEspacio,
    required String uidNfc,
    required double latitudInicio,
    required double longitudInicio,
  }) async {
    try {
      final dynamic respuesta = await supabase.rpc(
        'iniciar_labor_cobertura',
        params: {
          'p_id_espacio': idEspacio,
          'p_uid_nfc': uidNfc,
          'p_latitud_inicio': latitudInicio,
          'p_longitud_inicio': longitudInicio,
        },
      );

      // La nueva RPC devuelve una fila TABLE, convertida a mapa.
      final dynamic fila = respuesta is List && respuesta.isNotEmpty
          ? respuesta.first
          : respuesta;
      final Map<String, dynamic> data = _aMapaRespuesta(
        fila,
        operacion: 'iniciar la cobertura',
      );
      if (data['id_registro_aseo'] == null) {
        throw const RemoteRejectedException(
          'El servidor no devolvió el registro de la cobertura.',
        );
      }
      return <String, dynamic>{'ok': true, ...data};
    } catch (error) {
      _lanzarErrorRemoto(error);
    }
  }

  // ============================================================
  // FINALIZAR LABOR ONLINE
  // ============================================================

  /// Algunas RPC devuelven JSON (Map); las RPC RETURNS TABLE pueden
  /// devolver una lista de una fila. Nunca asumir éxito por el formato:
  /// si el resultado no confirma el término, consultar el registro
  /// remoto antes de cambiar el estado local del auxiliar.
  Map<String, dynamic>? _normalizarRespuestaTermino(dynamic respuesta) {
    dynamic valor = respuesta;

    if (valor is String) {
      try {
        valor = jsonDecode(valor);
      } catch (_) {
        return null;
      }
    }

    if (valor is Map) {
      return Map<String, dynamic>.from(valor);
    }

    if (valor is List && valor.length == 1 && valor.first is Map) {
      return Map<String, dynamic>.from(valor.first as Map);
    }

    return null;
  }

  /// Reconciliación de una respuesta ambigua del servidor. SOLO LECTURA.
  /// No modifica registro_aseo, no borra Hive, ni crea un término offline.
  /// Un término normal debe tener fecha_hora_fin e id_nfc_fin; el usuario
  /// autenticado debe ser el dueño del registro.
  Future<Map<String, dynamic>> _confirmarTerminoEnServidor({
    required int idRegistroRemoto,
  }) async {
    final User? usuario = supabase.auth.currentUser;
    if (usuario == null) {
      throw const RemoteRejectedException(
        'No hay sesión autenticada para confirmar el término de la labor.',
      );
    }

    try {
      final Map<String, dynamic>? fila = await supabase
          .from('registro_aseo')
          .select('id_registro_aseo, fecha_hora_fin, id_nfc_fin')
          .eq('id_registro_aseo', idRegistroRemoto)
          .eq('id_usuario', usuario.id)
          .maybeSingle();

      final dynamic fechaTermino = fila?['fecha_hora_fin'];
      final dynamic idNfcFin = fila?['id_nfc_fin'];

      if (fila == null || fechaTermino == null || idNfcFin == null) {
        throw const RemoteRejectedException(
          'El servidor devolvió una respuesta inesperada y no se pudo '
          'confirmar el término normal de la labor. No se modificó '
          'el estado local; revisa el registro en Supabase.',
        );
      }

      return <String, dynamic>{
        'ok': true,
        'id_registro_aseo': idRegistroRemoto,
        'fecha_hora_fin': fechaTermino,
        'mensaje': 'Término de labor confirmado en Supabase.',
      };
    } on RemoteRejectedException {
      rethrow;
    } catch (_) {
      // Si la consulta de confirmación falla, la RPC pudo haber efectuado
      // el cierre. No registrar otro término offline: sería ambiguo.
      throw const RemoteRejectedException(
        'El servidor respondió de forma inesperada y no fue posible '
        'verificar si la labor quedó finalizada. No se generó un término '
        'offline para evitar duplicaciones. Revisa Supabase antes '
        'de volver a intentarlo.',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> finalizarLabor({
    required int idRegistroRemoto,
    required String uidNfc,
    required double latitudFin,
    required double longitudFin,
  }) async {
    try {
      final dynamic respuesta = await supabase.rpc(
        'validar_termino_labor_aseo',
        params: {
          'p_id_registro_aseo': idRegistroRemoto,
          'p_uid_nfc': uidNfc,
          'p_latitud_fin': latitudFin,
          'p_longitud_fin': longitudFin,
        },
      );

      final Map<String, dynamic>? data = _normalizarRespuestaTermino(respuesta);

      if (data != null && data['ok'] == false) {
        // Rechazo explícito: no sortear reglas de negocio con la caché.
        throw RemoteRejectedException(
          (data['mensaje'] ?? 'No fue posible finalizar la labor.').toString(),
        );
      }

      if (data != null && data['ok'] == true) {
        return data;
      }

      // JSON nulo, texto, lista vacía o estructura sin confirmación:
      // verificar si la RPC registró el término antes de decidir.
      return await _confirmarTerminoEnServidor(
        idRegistroRemoto: idRegistroRemoto,
      );
    } catch (error) {
      _lanzarErrorRemoto(error);
    }
  }

  // ============================================================
  // ESTADO CIERRE EXCEPCIONAL PROPIO (SOLO LECTURA)
  // ============================================================

  @override
  Future<Map<String, dynamic>> consultarEstadoCierreExcepcional({
    required int idRegistroRemoto,
  }) async {
    try {
      final dynamic respuesta = await supabase.rpc(
        'consultar_estado_cierre_excepcional_auxiliar',
        params: <String, dynamic>{'p_id_registro': idRegistroRemoto},
      );

      final Map<String, dynamic> data = _aMapaRespuesta(
        respuesta,
        operacion: 'consultar el cierre excepcional',
      );
      if (data['ok'] != true) {
        throw const RemoteRejectedException(
          'No fue posible consultar el cierre excepcional.',
        );
      }
      return data;
    } catch (error) {
      _lanzarErrorRemoto(error);
    }
  }

  // ============================================================
  // SINCRONIZAR REGISTRO PENDIENTE
  // ============================================================

  @override
  Future<Map<String, dynamic>> enviarRegistroPendiente(
    Map<String, dynamic> payload,
  ) async {
    try {
      final String idLocal =
          (payload['id_local_sincronizacion'] ??
                  payload['id_local'] ??
                  payload['id_local_labor'] ??
                  '')
              .toString()
              .trim();

      if (idLocal.isEmpty) {
        throw const RemoteRejectedException(
          'El registro pendiente no posee identificador local.',
        );
      }

      final dynamic respuesta = await supabase.rpc(
        'sincronizar_registro_offline',
        params: {
          'p_id_local': idLocal,
          'p_id_registro_remoto': _aInt(payload['id_registro_remoto']),
          'p_id_espacio': _aInt(payload['id_espacio']),
          'p_fecha_hora_inicio': payload['fecha_hora_inicio'],
          'p_fecha_hora_fin': payload['fecha_hora_fin'],
          'p_latitud_inicio': _aDouble(payload['latitud_inicio']),
          'p_longitud_inicio': _aDouble(payload['longitud_inicio']),
          'p_latitud_fin': _aDouble(payload['latitud_fin']),
          'p_longitud_fin': _aDouble(payload['longitud_fin']),
          'p_uid_nfc': (payload['uid_nfc_inicio'] ?? payload['uid_nfc'] ?? '')
              .toString(),
          'p_estado': payload['estado_aseo']?.toString(),
          'p_comentario': payload['comentario']?.toString(),
          'p_tipo_observacion': payload['tipo_observacion']?.toString(),
          'p_detalle_observacion': payload['detalle_observacion']?.toString(),
        },
      );

      final Map<String, dynamic> data = _aMapaRespuesta(
        respuesta,
        operacion: 'sincronizar el registro pendiente',
      );

      if (data['ok'] != true) {
        throw const RemoteRejectedException(
          'No fue posible sincronizar el registro pendiente.',
        );
      }

      return data;
    } catch (error) {
      _lanzarErrorRemoto(error);
    }
  }

  // ============================================================
  // SINCRONIZAR EVIDENCIA PENDIENTE
  // ============================================================

  @override
  Future<void> enviarEvidenciaPendiente({
    required String idRegistroRemoto,
    required Map<String, dynamic> evidencia,
  }) async {
    try {
      final User? usuario = supabase.auth.currentUser;

      if (usuario == null) {
        throw const RemoteRejectedException(
          'No existe una sesión autenticada.',
        );
      }

      final int? idRegistro = _aInt(idRegistroRemoto);

      if (idRegistro == null) {
        throw const RemoteRejectedException(
          'El identificador remoto del registro no es válido.',
        );
      }

      final String base64 = (evidencia['bytes_base64'] ?? '').toString();

      if (base64.isEmpty) {
        throw const RemoteRejectedException(
          'La evidencia pendiente no contiene datos de imagen.',
        );
      }

      final bytes = base64Decode(base64);

      final String mimeType = (evidencia['mime_type'] ?? 'image/jpeg')
          .toString()
          .toLowerCase();

      final String extension;
      if (mimeType == 'image/png') {
        extension = 'png';
      } else if (mimeType == 'image/webp') {
        extension = 'webp';
      } else {
        extension = 'jpg';
      }

      final String idPendiente = (evidencia['id_pendiente'] ?? 'pendiente')
          .toString()
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

      final int indice = _aInt(evidencia['indice_evidencia']) ?? 0;

      final String nombreArchivo =
          'offline_${idPendiente}_${indice + 1}.$extension';

      final String rutaArchivo =
          '${usuario.id}/'
          '$idRegistro/'
          '$nombreArchivo';

      await supabase.storage
          .from('evidencias-aseo')
          .uploadBinary(
            rutaArchivo,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );

      final dynamic respuesta = await supabase.rpc(
        'registrar_evidencia_sincronizada',
        params: {
          'p_id_registro_aseo': idRegistro,
          'p_ruta_archivo': rutaArchivo,
          'p_nombre_archivo': nombreArchivo,
          'p_fecha_fotografia': evidencia['fecha_fotografia'],
        },
      );

      final Map<String, dynamic> data = _aMapaRespuesta(
        respuesta,
        operacion: 'registrar la evidencia sincronizada',
      );

      if (data['ok'] != true) {
        throw const RemoteRejectedException(
          'No fue posible registrar la evidencia sincronizada.',
        );
      }
    } catch (error) {
      _lanzarErrorRemoto(error);
    }
  }

  // ============================================================
  // MARCAR REGISTRO COMO SINCRONIZADO
  // ============================================================

  @override
  Future<void> marcarRegistroSincronizado({
    required String idRegistroRemoto,
  }) async {
    try {
      final int? idRegistro = _aInt(idRegistroRemoto);

      if (idRegistro == null) {
        throw const RemoteRejectedException(
          'El identificador remoto del registro no es válido.',
        );
      }

      final dynamic respuesta = await supabase.rpc(
        'marcar_registro_sincronizado',
        params: {'p_id_registro_aseo': idRegistro},
      );

      final Map<String, dynamic> data = _aMapaRespuesta(
        respuesta,
        operacion: 'marcar el registro como sincronizado',
      );

      if (data['ok'] != true) {
        throw const RemoteRejectedException(
          'No fue posible confirmar la sincronización.',
        );
      }
    } catch (error) {
      _lanzarErrorRemoto(error);
    }
  }
}
