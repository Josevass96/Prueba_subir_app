import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;

import '../remote/remote_backend.dart';
import '../storage/local_storage.dart';
import 'registro_final_fallback_service.dart';
import 'sincronizacion_service.dart';

class SincronizacionAutomaticaService with WidgetsBindingObserver {
  final LocalStorage localStorage;
  final RemoteBackend remoteBackend;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  StreamSubscription<AuthState>? _authSubscription;

  // Reintenta los pendientes también cuando la conectividad móvil
  // sigue marcada como activa y no se emite un evento de reconexión.
  Timer? _reintentoPeriodico;

  SincronizacionService? _sincronizacionService;

  bool _iniciado = false;
  bool _evaluandoSincronizacion = false;
  bool _enPrimerPlano = true;

  SincronizacionAutomaticaService({
    required this.localStorage,
    required this.remoteBackend,
  });

  // =============================================================
  // INICIAR SERVICIO
  // =============================================================

  void iniciar() {
    if (_iniciado) {
      return;
    }

    _iniciado = true;

    _sincronizacionService = SincronizacionService(
      localStorage: localStorage,
      remoteBackend: remoteBackend,
    );

    WidgetsBinding.instance.addObserver(this);

    // -----------------------------------------------------------
    // ESCUCHAR CAMBIOS DE CONECTIVIDAD
    // -----------------------------------------------------------

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      _,
    ) {
      // connectivity_plus indica interfaces, no acceso real a Internet.
      // Cualquier cambio puede ser una recuperación de conectividad,
      // aunque el plugin no la clasifique correctamente como Wi-Fi/datos.
      unawaited(_intentarSincronizar());
    });

    // -----------------------------------------------------------
    // ESCUCHAR SESIÓN DE SUPABASE
    // -----------------------------------------------------------

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      AuthState data,
    ) {
      if (data.session != null) {
        unawaited(_intentarSincronizar());
      }
    });

    _reintentoPeriodico = Timer.periodic(const Duration(seconds: 45), (_) {
      if (_enPrimerPlano) {
        unawaited(_intentarSincronizar());
      }
    });

    // -----------------------------------------------------------
    // REVISAR PENDIENTES AL INICIAR
    // -----------------------------------------------------------

    unawaited(_intentarSincronizar());
  }

  // =============================================================
  // APP VUELVE A PRIMER PLANO
  // =============================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enPrimerPlano = true;
      unawaited(_intentarSincronizar());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _enPrimerPlano = false;
    }
  }

  // =============================================================
  // INTENTAR SINCRONIZAR
  // =============================================================

  Future<void> _intentarSincronizar() async {
    if (_evaluandoSincronizacion) {
      return;
    }

    _evaluandoSincronizacion = true;

    try {
      final User? usuario = Supabase.instance.client.auth.currentUser;

      // Sin sesión no podemos enviar nada.
      if (usuario == null) {
        return;
      }

      // Antes de consultar la red revisamos si
      // realmente existen pendientes para este usuario.
      final List<Map<String, dynamic>> pendientes = localStorage
          .listarPendientes(usuario.id);

      if (pendientes.isEmpty) {
        return;
      }

      // No saltamos la sincronización porque connectivity_plus indique
      // "none": en algunos dispositivos la interfaz informada puede no
      // coincidir con el acceso real al servidor. Comprobamos Supabase.
      final bool backendResponde = await RegistroFinalFallbackService(
        localStorage: localStorage,
        supabase: Supabase.instance.client,
      ).backendDisponible();

      if (!backendResponde) {
        debugPrint('REGISERV: Supabase no disponible; pendientes conservados.');
        return;
      }

      // Evita procesar los pendientes del usuario anterior si la sesión
      // cambió durante la comprobación de conectividad.
      if (Supabase.instance.client.auth.currentUser?.id != usuario.id) {
        return;
      }

      final SincronizacionService? servicio = _sincronizacionService;

      if (servicio == null) {
        return;
      }

      final SincronizacionResultado resultado = await servicio
          .sincronizarPendientes(idUsuario: usuario.id);

      debugPrint(
        'SINCRONIZACIÓN REGISERV: '
        'encontrados=${resultado.encontrados}, '
        'sincronizados=${resultado.sincronizados}, '
        'errores=${resultado.conError}, '
        'backendNoDisponible='
        '${resultado.backendNoDisponible}',
      );
    } catch (error) {
      // La sincronización automática nunca debe
      // cerrar ni bloquear la aplicación.
      // Los pendientes permanecen en Hive.
      debugPrint(
        'ERROR SINCRONIZACIÓN AUTOMÁTICA: '
        '$error',
      );
    } finally {
      _evaluandoSincronizacion = false;
    }
  }

  // =============================================================
  // DETENER SERVICIO
  // =============================================================

  Future<void> detener() async {
    if (!_iniciado) {
      return;
    }

    WidgetsBinding.instance.removeObserver(this);

    await _connectivitySubscription?.cancel();

    await _authSubscription?.cancel();
    _reintentoPeriodico?.cancel();
    _reintentoPeriodico = null;

    _connectivitySubscription = null;
    _authSubscription = null;

    _sincronizacionService = null;

    _iniciado = false;
    _evaluandoSincronizacion = false;
  }
}
