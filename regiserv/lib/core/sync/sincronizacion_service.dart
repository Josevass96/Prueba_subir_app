import '../remote/remote_backend.dart';
import '../storage/local_storage.dart';

class SincronizacionResultado {
  final int encontrados;
  final int sincronizados;
  final int conError;
  final bool backendNoDisponible;

  const SincronizacionResultado({
    required this.encontrados,
    required this.sincronizados,
    required this.conError,
    required this.backendNoDisponible,
  });

  bool get sinPendientes => encontrados == 0;
}

class SincronizacionService {
  final LocalStorage localStorage;
  final RemoteBackend remoteBackend;

  // Bloqueo compartido entre todas las instancias del servicio.
  // Evita que la sincronización automática y la manual procesen
  // la misma cola al mismo tiempo.
  static bool _sincronizando = false;

  SincronizacionService({
    required this.localStorage,
    required this.remoteBackend,
  });

  bool get sincronizando => _sincronizando;

  Future<SincronizacionResultado> sincronizarPendientes({
    required String idUsuario,
  }) async {
    if (_sincronizando) {
      return const SincronizacionResultado(
        encontrados: 0,
        sincronizados: 0,
        conError: 0,
        backendNoDisponible: false,
      );
    }

    _sincronizando = true;

    int sincronizados = 0;
    int conError = 0;
    bool backendNoDisponible = false;

    final List<Map<String, dynamic>> pendientes = localStorage.listarPendientes(
      idUsuario,
    );

    try {
      for (final Map<String, dynamic> pendiente in pendientes) {
        final String idLocal = (pendiente['id_local'] ?? '').toString();

        if (idLocal.isEmpty) {
          continue;
        }

        final int intentosAnteriores = _aInt(pendiente['intentos']) ?? 0;

        final int intentoActual = intentosAnteriores + 1;

        await localStorage.actualizarPendiente(
          idLocal: idLocal,
          estado: 'Sincronizando',
          ultimoError: null,
          intentos: intentoActual,
        );

        try {
          final Map<String, dynamic> payload = _aMapa(pendiente['payload']);

          payload['id_local_sincronizacion'] = idLocal;

          final Map<String, dynamic> resultadoRegistro = await remoteBackend
              .enviarRegistroPendiente(payload);

          final String idRegistroRemoto =
              (resultadoRegistro['id_registro_aseo'] ?? '').toString();

          if (idRegistroRemoto.isEmpty) {
            throw StateError(
              'El backend no entregó el ID del registro sincronizado.',
            );
          }

          final List<Map<String, dynamic>> evidencias = _aListaMap(
            pendiente['evidencias'],
          );

          for (int i = 0; i < evidencias.length; i++) {
            final Map<String, dynamic> evidencia = <String, dynamic>{
              ...evidencias[i],
              'id_pendiente': idLocal,
              'indice_evidencia': i,
            };

            await remoteBackend.enviarEvidenciaPendiente(
              idRegistroRemoto: idRegistroRemoto,
              evidencia: evidencia,
            );
          }

          await remoteBackend.marcarRegistroSincronizado(
            idRegistroRemoto: idRegistroRemoto,
          );

          // Solo se elimina después de que:
          // 1) registro,
          // 2) todas las evidencias y
          // 3) confirmación final
          // hayan sido aceptados por el backend.
          await localStorage.eliminarPendiente(idLocal);

          sincronizados++;
        } on RemoteUnavailableException catch (error) {
          await localStorage.actualizarPendiente(
            idLocal: idLocal,
            estado: 'Pendiente',
            ultimoError: error.toString(),
            intentos: intentoActual,
          );

          backendNoDisponible = true;

          // Si el backend no está disponible,
          // no tiene sentido golpear los demás
          // pendientes en este mismo ciclo.
          break;
        } catch (error) {
          await localStorage.actualizarPendiente(
            idLocal: idLocal,
            estado: 'Error',
            ultimoError: error.toString(),
            intentos: intentoActual,
          );

          conError++;

          // Un pendiente con error de datos no
          // debe impedir intentar los siguientes.
          continue;
        }
      }

      return SincronizacionResultado(
        encontrados: pendientes.length,
        sincronizados: sincronizados,
        conError: conError,
        backendNoDisponible: backendNoDisponible,
      );
    } finally {
      _sincronizando = false;
    }
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

  Map<String, dynamic> _aMapa(dynamic valor) {
    if (valor is! Map) {
      return <String, dynamic>{};
    }

    return Map<String, dynamic>.from(valor);
  }

  List<Map<String, dynamic>> _aListaMap(dynamic valor) {
    if (valor is! List) {
      return <Map<String, dynamic>>[];
    }

    return valor
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}
