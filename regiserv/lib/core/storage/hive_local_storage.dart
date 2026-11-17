import 'dart:convert';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'local_storage.dart';

class HiveLocalStorage implements LocalStorage {
  HiveLocalStorage._();

  static final HiveLocalStorage instance = HiveLocalStorage._();

  static const String _boxDatos = 'regiserv_datos_locales';

  static const String _boxPendientes = 'regiserv_cola_sincronizacion';

  Box<String>? _datos;
  Box<String>? _pendientes;

  bool get estaInicializado => _datos != null && _pendientes != null;

  @override
  Future<void> inicializar() async {
    if (estaInicializado) {
      return;
    }

    await Hive.initFlutter();

    _datos = await Hive.openBox<String>(_boxDatos);

    _pendientes = await Hive.openBox<String>(_boxPendientes);
  }

  Box<String> get _datosBox {
    final box = _datos;

    if (box == null) {
      throw StateError('HiveLocalStorage no está inicializado.');
    }

    return box;
  }

  Box<String> get _pendientesBox {
    final box = _pendientes;

    if (box == null) {
      throw StateError('HiveLocalStorage no está inicializado.');
    }

    return box;
  }

  String _keyPerfil(String idUsuario) => 'perfil_$idUsuario';

  String _keyCache(String idUsuario) => 'cache_$idUsuario';

  String _keyLabor(String idUsuario) => 'labor_$idUsuario';

  String _codificar(Map<String, dynamic> data) {
    return jsonEncode(data);
  }

  Map<String, dynamic>? _decodificar(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return null;
    }

    final dynamic decoded = jsonDecode(valor);

    if (decoded is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(decoded);
  }

  @override
  Future<void> guardarPerfil({
    required String idUsuario,
    required Map<String, dynamic> perfil,
  }) async {
    await _datosBox.put(_keyPerfil(idUsuario), _codificar(perfil));
  }

  @override
  Map<String, dynamic>? obtenerPerfil(String idUsuario) {
    return _decodificar(_datosBox.get(_keyPerfil(idUsuario)));
  }

  @override
  Future<void> guardarCacheOperacional({
    required String idUsuario,
    required Map<String, dynamic> cache,
  }) async {
    final Map<String, dynamic> data = {
      ...cache,
      'fecha_cache': DateTime.now().toUtc().toIso8601String(),
    };

    await _datosBox.put(_keyCache(idUsuario), _codificar(data));
  }

  @override
  Map<String, dynamic>? obtenerCacheOperacional(String idUsuario) {
    return _decodificar(_datosBox.get(_keyCache(idUsuario)));
  }

  @override
  Future<void> guardarLaborEnCurso({
    required String idUsuario,
    required Map<String, dynamic> labor,
  }) async {
    await _datosBox.put(_keyLabor(idUsuario), _codificar(labor));
  }

  @override
  Map<String, dynamic>? obtenerLaborEnCurso(String idUsuario) {
    return _decodificar(_datosBox.get(_keyLabor(idUsuario)));
  }

  @override
  Future<void> eliminarLaborEnCurso(String idUsuario) async {
    await _datosBox.delete(_keyLabor(idUsuario));
  }

  @override
  Future<String> agregarPendiente({
    required String idUsuario,
    required String tipo,
    required Map<String, dynamic> payload,
    List<Map<String, dynamic>> evidencias = const [],
  }) async {
    final String idLocal =
        '${idUsuario}_${DateTime.now().microsecondsSinceEpoch}';

    final Map<String, dynamic> item = {
      'id_local': idLocal,
      'id_usuario': idUsuario,
      'tipo': tipo,
      'estado': 'Pendiente',
      'intentos': 0,
      'ultimo_error': null,
      'fecha_creacion': DateTime.now().toUtc().toIso8601String(),
      'fecha_ultimo_intento': null,
      'payload': payload,
      'evidencias': evidencias,
    };

    await _pendientesBox.put(idLocal, _codificar(item));

    return idLocal;
  }

  @override
  List<Map<String, dynamic>> listarPendientes(String idUsuario) {
    final List<Map<String, dynamic>> items = [];

    for (final String valor in _pendientesBox.values) {
      final Map<String, dynamic>? item = _decodificar(valor);

      if (item == null) {
        continue;
      }

      if ((item['id_usuario'] ?? '').toString() != idUsuario) {
        continue;
      }

      items.add(item);
    }

    items.sort(
      (a, b) => (a['fecha_creacion'] ?? '').toString().compareTo(
        (b['fecha_creacion'] ?? '').toString(),
      ),
    );

    return items;
  }

  @override
  Future<void> actualizarPendiente({
    required String idLocal,
    String? estado,
    String? ultimoError,
    int? intentos,
  }) async {
    final Map<String, dynamic>? actual = _decodificar(
      _pendientesBox.get(idLocal),
    );

    if (actual == null) {
      return;
    }

    if (estado != null) {
      actual['estado'] = estado;
    }

    actual['ultimo_error'] = ultimoError;

    if (intentos != null) {
      actual['intentos'] = intentos;
    }

    actual['fecha_ultimo_intento'] = DateTime.now().toUtc().toIso8601String();

    await _pendientesBox.put(idLocal, _codificar(actual));
  }

  @override
  Future<void> eliminarPendiente(String idLocal) async {
    await _pendientesBox.delete(idLocal);
  }

  @override
  Future<void> limpiarDatosUsuario(String idUsuario) async {
    await _datosBox.delete(_keyPerfil(idUsuario));

    await _datosBox.delete(_keyCache(idUsuario));

    await _datosBox.delete(_keyLabor(idUsuario));

    // La cola pendiente NO se elimina aquí.
    // Debe conservarse hasta sincronizarse.
  }
}
