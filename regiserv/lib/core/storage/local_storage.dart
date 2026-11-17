abstract class LocalStorage {
  Future<void> inicializar();

  Future<void> guardarPerfil({
    required String idUsuario,
    required Map<String, dynamic> perfil,
  });

  Map<String, dynamic>? obtenerPerfil(String idUsuario);

  Future<void> guardarCacheOperacional({
    required String idUsuario,
    required Map<String, dynamic> cache,
  });

  Map<String, dynamic>? obtenerCacheOperacional(String idUsuario);

  Future<void> guardarLaborEnCurso({
    required String idUsuario,
    required Map<String, dynamic> labor,
  });

  Map<String, dynamic>? obtenerLaborEnCurso(String idUsuario);

  Future<void> eliminarLaborEnCurso(String idUsuario);

  Future<String> agregarPendiente({
    required String idUsuario,
    required String tipo,
    required Map<String, dynamic> payload,
    List<Map<String, dynamic>> evidencias = const [],
  });

  List<Map<String, dynamic>> listarPendientes(String idUsuario);

  Future<void> actualizarPendiente({
    required String idLocal,
    String? estado,
    String? ultimoError,
    int? intentos,
  });

  Future<void> eliminarPendiente(String idLocal);

  Future<void> limpiarDatosUsuario(String idUsuario);
}
