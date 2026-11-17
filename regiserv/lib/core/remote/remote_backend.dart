// ================================================================
// CONTRATO DEL BACKEND REMOTO
// ================================================================
//
// RegiServ trabaja contra este contrato y no contra un proveedor
// específico.
//
// Hoy:
//   SupabaseRemoteBackend implements RemoteBackend
//
// Futuro:
//   AzureRemoteBackend implements RemoteBackend
// ================================================================

class RemoteRejectedException implements Exception {
  final String message;

  const RemoteRejectedException(this.message);

  @override
  String toString() => message;
}

class RemoteUnavailableException implements Exception {
  final String message;

  const RemoteUnavailableException(this.message);

  @override
  String toString() => message;
}

abstract class RemoteBackend {
  String get nombreProveedor;

  Future<Map<String, dynamic>> obtenerCacheOperacional({
    required String idUsuario,
  });

  // =============================================================
  // LABORES
  // =============================================================

  Future<Map<String, dynamic>> iniciarLabor({
    required int idEspacio,
    required String uidNfc,
    required double latitudInicio,
    required double longitudInicio,
  });

  // Inicia una cobertura autorizada por NFC/GPS sin asignación propia.
  Future<Map<String, dynamic>> iniciarLaborCobertura({
    required int idEspacio,
    required String uidNfc,
    required double latitudInicio,
    required double longitudInicio,
  });

  Future<Map<String, dynamic>> finalizarLabor({
    required int idRegistroRemoto,
    required String uidNfc,
    required double latitudFin,
    required double longitudFin,
  });

  // Consulta SOLO el estado del cierre excepcional de una labor propia.
  // No modifica registros ni libera almacenamiento local por sí misma.
  Future<Map<String, dynamic>> consultarEstadoCierreExcepcional({
    required int idRegistroRemoto,
  });

  // =============================================================
  // SINCRONIZACIÓN
  // =============================================================

  Future<Map<String, dynamic>> enviarRegistroPendiente(
    Map<String, dynamic> payload,
  );

  Future<void> enviarEvidenciaPendiente({
    required String idRegistroRemoto,
    required Map<String, dynamic> evidencia,
  });

  Future<void> marcarRegistroSincronizado({required String idRegistroRemoto});
}
