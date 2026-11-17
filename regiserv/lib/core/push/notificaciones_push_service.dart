import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/sesion_data.dart';

/// Registra identificadores de instalación FCM (FID) solamente para Supervisor, Supervisor Jefe y Mantención.
/// En dispositivos compartidos, el FID se retira/desregistra ANTES de salir.
/// No se ejecuta en Web, iOS ni otras plataformas todavía no configuradas.
class NotificacionesPushService {
  NotificacionesPushService._();

  static final NotificacionesPushService instance =
      NotificacionesPushService._();

  final SupabaseClient _supabase = Supabase.instance.client;
  StreamSubscription<String>? _suscripcionInstalacion;
  Future<void> _ultimaOperacion = Future<void>.value();

  bool _bloqueado = true;
  String? _instalacionRegistrada;
  String? _usuarioRegistrado;

  bool get _disponible =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      Firebase.apps.isNotEmpty;

  bool _rolConNotificaciones(String rol) =>
      rol == 'Supervisor' || rol == 'Supervisor Jefe' || rol == 'Mantención';

  bool _sesionValidada() {
    final String? idActual = _supabase.auth.currentUser?.id;
    return idActual != null &&
        SesionData.usuarioIdActual == idActual &&
        _rolConNotificaciones(SesionData.rolActual);
  }

  // Evita que un registro pendiente se complete después del cierre de sesión.
  Future<void> _enOrden(Future<void> Function() operacion) {
    final Future<void> siguiente = _ultimaOperacion.then((_) => operacion());
    _ultimaOperacion = siguiente.catchError((Object error, StackTrace st) {
      debugPrint('ERROR COLA NOTIFICACIONES PUSH: $error');
    });
    return siguiente;
  }

  /// Se invoca una vez, después de Firebase.initializeApp().
  void iniciar() {
    if (!_disponible || _suscripcionInstalacion != null) {
      return;
    }

    _suscripcionInstalacion = FirebaseMessaging.instance.onRegistered.listen(
      (String identificadorInstalacion) {
        unawaited(
          _enOrden(() async {
            if (_bloqueado || !_sesionValidada()) {
              return;
            }
            await _guardarInstalacion(identificadorInstalacion);
          }).catchError((Object error) {
            debugPrint('ERROR REGISTRANDO INSTALACIÓN FCM: $error');
          }),
        );
      },
      onError: (Object error) {
        debugPrint('ERROR EVENTO REGISTRO FCM: $error');
      },
    );
  }

  /// Se llama DESPUÉS de autenticar y validar el perfil de RegiServ.
  /// Si entra un Auxiliar, desregistra la instalación de push del dispositivo.
  Future<void> registrarAlIniciarSesion({required String rol}) async {
    if (!_disponible) {
      return;
    }

    _bloqueado = false;

    try {
      await _enOrden(() async {
        if (!_rolConNotificaciones(rol)) {
          _bloqueado = true;
          await _desregistrarInstalacionEnDispositivo();
          return;
        }

        if (!_sesionValidada() || SesionData.rolActual != rol) {
          return;
        }

        final NotificationSettings permiso = await FirebaseMessaging.instance
            .requestPermission(alert: true, badge: true, sound: true);

        if (permiso.authorizationStatus != AuthorizationStatus.authorized &&
            permiso.authorizationStatus != AuthorizationStatus.provisional) {
          debugPrint('NOTIFICACIONES PUSH: permiso no concedido.');
          _bloqueado = true;
          await _retirarInstalacionEnServidor();
          await _desregistrarInstalacionEnDispositivo();
          return;
        }

        if (_bloqueado || !_sesionValidada()) {
          return;
        }

        // El FID se obtiene exclusivamente en el evento onRegistered.
        // La suscripción fue creada en iniciar(), antes de register().
        await FirebaseMessaging.instance.register();
      });
    } catch (error) {
      // El registro push nunca impide que el funcionario use RegiServ.
      debugPrint('ERROR REGISTRANDO DISPOSITIVO PUSH: $error');
    }
  }

  Future<void> _guardarInstalacion(String instalacionId) async {
    if (_bloqueado || !_sesionValidada()) {
      return;
    }

    final String? usuario = _supabase.auth.currentUser?.id;
    if (usuario == null) {
      return;
    }

    await _supabase.rpc(
      'registrar_dispositivo_push',
      params: <String, dynamic>{'p_token': instalacionId},
    );

    final String? instalacionAnterior = _instalacionRegistrada;
    final String? usuarioAnterior = _usuarioRegistrado;
    _instalacionRegistrada = instalacionId;
    _usuarioRegistrado = usuario;

    // Si Firebase rotó el FID, retiramos la fila del identificador anterior.
    if (usuarioAnterior == usuario &&
        instalacionAnterior != null &&
        instalacionAnterior != instalacionId) {
      try {
        await _supabase.rpc(
          'retirar_dispositivo_push',
          params: <String, dynamic>{'p_token': instalacionAnterior},
        );
      } catch (error) {
        debugPrint('NO SE PUDO RETIRAR FID ANTERIOR: $error');
      }
    }
  }

  Future<void> _retirarInstalacionEnServidor() async {
    if (_supabase.auth.currentUser == null) {
      return;
    }

    final String? instalacionId = _instalacionRegistrada;
    if (instalacionId == null || instalacionId.isEmpty) {
      return;
    }

    try {
      await _supabase.rpc(
        'retirar_dispositivo_push',
        params: <String, dynamic>{'p_token': instalacionId},
      );
    } catch (error) {
      // Si no hay red, intentamos desregistrar el dispositivo en FCM.
      // No podemos garantizar el borrado remoto sin conexión.
      debugPrint('NO SE PUDO RETIRAR FID EN SUPABASE: $error');
    }
  }

  Future<void> _desregistrarInstalacionEnDispositivo() async {
    try {
      await FirebaseMessaging.instance.unregister();
    } catch (error) {
      debugPrint('NO SE PUDO DESREGISTRAR INSTALACIÓN FCM: $error');
    } finally {
      _instalacionRegistrada = null;
      _usuarioRegistrado = null;
    }
  }

  /// IMPORTANTE: llamar ANTES de supabase.auth.signOut(),
  /// porque la RPC necesita la sesión autenticada.
  Future<void> retirarAntesCerrarSesion() async {
    if (!_disponible) {
      return;
    }

    _bloqueado = true;

    try {
      await _enOrden(() async {
        try {
          await _retirarInstalacionEnServidor();
        } finally {
          await _desregistrarInstalacionEnDispositivo();
        }
      });
    } catch (error) {
      debugPrint('ERROR RETIRANDO DISPOSITIVO PUSH: $error');
    }
  }

  /// Respaldo para cualquier salida de Supabase realizada fuera del Home.
  /// Solo desregistra la instalación en FCM: ya no hay JWT para la RPC.
  Future<void> invalidarDespuesDeSalir() async {
    if (!_disponible) {
      return;
    }

    _bloqueado = true;
    try {
      await _enOrden(_desregistrarInstalacionEnDispositivo);
    } catch (error) {
      debugPrint('ERROR LIMPIANDO TOKEN DESPUÉS DE SALIR: $error');
    }
  }
}
