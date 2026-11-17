import '../remote/remote_backend.dart';
import '../storage/local_storage.dart';

class CacheOperacionalService {
  final LocalStorage localStorage;
  final RemoteBackend remoteBackend;

  const CacheOperacionalService({
    required this.localStorage,
    required this.remoteBackend,
  });

  Future<bool> actualizarCacheAuxiliar({required String idUsuario}) async {
    try {
      final Map<String, dynamic> cache = await remoteBackend
          .obtenerCacheOperacional(idUsuario: idUsuario);

      await localStorage.guardarCacheOperacional(
        idUsuario: idUsuario,
        cache: cache,
      );

      return true;
    } catch (_) {
      // Importante:
      // si falla Internet o el backend,
      // NO borramos la última caché válida.
      return false;
    }
  }

  Map<String, dynamic>? obtenerCacheActual({required String idUsuario}) {
    return localStorage.obtenerCacheOperacional(idUsuario);
  }

  bool existeCache({required String idUsuario}) {
    return obtenerCacheActual(idUsuario: idUsuario) != null;
  }
}
