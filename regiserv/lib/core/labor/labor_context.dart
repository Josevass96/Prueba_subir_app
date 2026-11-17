class LaborContext {
  final String idLocal;
  final String idUsuario;
  final int idEspacio;

  final int? idRegistroRemoto;

  final String origen;
  final String estadoLocal;

  final bool requiereSincronizacion;

  final String uidNfcInicio;
  final int? idNfcInicio;

  final DateTime fechaHoraInicio;
  final DateTime? fechaHoraFin;

  final double latitudInicio;
  final double longitudInicio;

  final double? latitudFin;
  final double? longitudFin;

  final String lugar;
  final String nombreAuxiliar;

  final DateTime? fechaCacheValidacion;

  final double? radioLatitud;
  final double? radioLongitud;
  final double? radioMetros;

  final double? distanciaInicioMetros;

  const LaborContext({
    required this.idLocal,
    required this.idUsuario,
    required this.idEspacio,
    required this.idRegistroRemoto,
    required this.origen,
    required this.estadoLocal,
    required this.requiereSincronizacion,
    required this.uidNfcInicio,
    required this.idNfcInicio,
    required this.fechaHoraInicio,
    required this.fechaHoraFin,
    required this.latitudInicio,
    required this.longitudInicio,
    required this.latitudFin,
    required this.longitudFin,
    required this.lugar,
    required this.nombreAuxiliar,
    required this.fechaCacheValidacion,
    required this.radioLatitud,
    required this.radioLongitud,
    required this.radioMetros,
    required this.distanciaInicioMetros,
  });

  bool get esOffline => idRegistroRemoto == null || origen == 'offline';

  bool get tieneRegistroRemoto => idRegistroRemoto != null;

  bool get estaEnCurso => estadoLocal == 'En curso';

  LaborContext copyWith({
    int? idRegistroRemoto,
    bool limpiarIdRegistroRemoto = false,
    String? origen,
    String? estadoLocal,
    bool? requiereSincronizacion,
    DateTime? fechaHoraFin,
    bool limpiarFechaHoraFin = false,
    double? latitudFin,
    bool limpiarLatitudFin = false,
    double? longitudFin,
    bool limpiarLongitudFin = false,
  }) {
    return LaborContext(
      idLocal: idLocal,
      idUsuario: idUsuario,
      idEspacio: idEspacio,
      idRegistroRemoto: limpiarIdRegistroRemoto
          ? null
          : idRegistroRemoto ?? this.idRegistroRemoto,
      origen: origen ?? this.origen,
      estadoLocal: estadoLocal ?? this.estadoLocal,
      requiereSincronizacion:
          requiereSincronizacion ?? this.requiereSincronizacion,
      uidNfcInicio: uidNfcInicio,
      idNfcInicio: idNfcInicio,
      fechaHoraInicio: fechaHoraInicio,
      fechaHoraFin: limpiarFechaHoraFin
          ? null
          : fechaHoraFin ?? this.fechaHoraFin,
      latitudInicio: latitudInicio,
      longitudInicio: longitudInicio,
      latitudFin: limpiarLatitudFin ? null : latitudFin ?? this.latitudFin,
      longitudFin: limpiarLongitudFin ? null : longitudFin ?? this.longitudFin,
      lugar: lugar,
      nombreAuxiliar: nombreAuxiliar,
      fechaCacheValidacion: fechaCacheValidacion,
      radioLatitud: radioLatitud,
      radioLongitud: radioLongitud,
      radioMetros: radioMetros,
      distanciaInicioMetros: distanciaInicioMetros,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id_local': idLocal,
      'id_usuario': idUsuario,
      'id_espacio': idEspacio,
      'id_registro_remoto': idRegistroRemoto,
      'origen': origen,
      'estado_local': estadoLocal,
      'requiere_sincronizacion': requiereSincronizacion,
      'uid_nfc_inicio': uidNfcInicio,
      'id_nfc_inicio': idNfcInicio,
      'fecha_hora_inicio': fechaHoraInicio.toUtc().toIso8601String(),
      'fecha_hora_fin': fechaHoraFin?.toUtc().toIso8601String(),
      'latitud_inicio': latitudInicio,
      'longitud_inicio': longitudInicio,
      'latitud_fin': latitudFin,
      'longitud_fin': longitudFin,
      'lugar': lugar,
      'nombre_auxiliar': nombreAuxiliar,
      'fecha_cache_validacion': fechaCacheValidacion?.toUtc().toIso8601String(),
      'radio_latitud': radioLatitud,
      'radio_longitud': radioLongitud,
      'radio_metros': radioMetros,
      'distancia_inicio_metros': distanciaInicioMetros,
    };
  }

  factory LaborContext.fromMap(Map<String, dynamic> map) {
    return LaborContext(
      idLocal: (map['id_local'] ?? '').toString(),
      idUsuario: (map['id_usuario'] ?? '').toString(),
      idEspacio: _aInt(map['id_espacio']) ?? 0,
      idRegistroRemoto: _aInt(map['id_registro_remoto']),
      origen: (map['origen'] ?? 'offline').toString(),
      estadoLocal: (map['estado_local'] ?? 'En curso').toString(),
      requiereSincronizacion: map['requiere_sincronizacion'] == true,
      uidNfcInicio: (map['uid_nfc_inicio'] ?? '').toString(),
      idNfcInicio: _aInt(map['id_nfc_inicio']),
      fechaHoraInicio: _aFecha(map['fecha_hora_inicio']) ?? DateTime.now(),
      fechaHoraFin: _aFecha(map['fecha_hora_fin']),
      latitudInicio: _aDouble(map['latitud_inicio']) ?? 0,
      longitudInicio: _aDouble(map['longitud_inicio']) ?? 0,
      latitudFin: _aDouble(map['latitud_fin']),
      longitudFin: _aDouble(map['longitud_fin']),
      lugar: (map['lugar'] ?? '').toString(),
      nombreAuxiliar: (map['nombre_auxiliar'] ?? '').toString(),
      fechaCacheValidacion: _aFecha(map['fecha_cache_validacion']),
      radioLatitud: _aDouble(map['radio_latitud']),
      radioLongitud: _aDouble(map['radio_longitud']),
      radioMetros: _aDouble(map['radio_metros']),
      distanciaInicioMetros: _aDouble(map['distancia_inicio_metros']),
    );
  }

  static int? _aInt(dynamic valor) {
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

  static double? _aDouble(dynamic valor) {
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

  static DateTime? _aFecha(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is DateTime) {
      return valor;
    }

    return DateTime.tryParse(valor.toString());
  }
}
