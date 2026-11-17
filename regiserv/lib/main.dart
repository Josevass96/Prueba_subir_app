import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';

import 'config/supabase_config.dart';
import 'data/sesion_data.dart';
import 'core/storage/hive_local_storage.dart';
import 'core/labor/labor_context.dart';
import 'core/remote/supabase_remote_backend.dart';
import 'core/sync/cache_operacional_service.dart';
import 'core/sync/sincronizacion_automatica_service.dart';
import 'core/push/notificaciones_push_service.dart';

import 'pages/auxiliar_home_page.dart';
import 'pages/labor_en_curso_page.dart';
import 'pages/registro_final_page.dart';
import 'pages/registro_final_offline_page.dart';
import 'pages/supervisor_home_page.dart';
import 'pages/supervisor_jefe_home_page.dart';
import 'pages/panel_web_supervisor_jefe_page.dart';
import 'pages/mantencion_home_page.dart';
import 'pages/cambiar_contrasena_page.dart';
import 'pages/recuperar_contrasena_page.dart';
import 'pages/restablecer_contrasena_page.dart';

// Devuelve al Auxiliar a su labor persistida, incluso tras cerrar la app.
// No crea registros nuevos ni modifica la información guardada en Hive.
Widget _destinoAuxiliarConLabor(String idUsuario) {
  try {
    final Map<String, dynamic>? datos = HiveLocalStorage.instance
        .obtenerLaborEnCurso(idUsuario);
    if (datos == null || datos['id_usuario']?.toString() != idUsuario) {
      return const AuxiliarHomePage();
    }

    final labor = LaborContext.fromMap(datos);
    if (labor.idEspacio <= 0 || labor.uidNfcInicio.isEmpty) {
      debugPrint('LABOR LOCAL INCOMPLETA: conservada para revisión.');
      return const AuxiliarHomePage();
    }

    if (labor.estadoLocal == 'En curso') {
      return LaborEnCursoPage(labor: labor);
    }

    // Si la aplicación se cerró después de validar el término,
    // recuperamos también el paso pendiente de completar evidencias.
    if (labor.estadoLocal == 'Finalizada pendiente de detalle') {
      if (labor.idRegistroRemoto != null && !labor.requiereSincronizacion) {
        return RegistroFinalPage(
          idRegistroAseo: labor.idRegistroRemoto!,
          nombreAuxiliar: labor.nombreAuxiliar,
          lugar: labor.lugar,
          horaInicio: labor.fechaHoraInicio,
          horaTermino: labor.fechaHoraFin ?? DateTime.now(),
        );
      }
      return RegistroFinalOfflinePage(labor: labor);
    }
  } catch (error) {
    debugPrint('ERROR RECUPERANDO LABOR PERSISTIDA: $error');
  }
  return const AuxiliarHomePage();
}

// =================================================================
// MAIN
// =================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // =============================================================
  // INICIALIZAR ALMACENAMIENTO LOCAL
  // =============================================================
  //
  // Debe estar disponible incluso cuando no exista conexión.
  // Esta capa solo conoce almacenamiento local.
  // No depende de Supabase, Azure ni de otro proveedor remoto.
  // =============================================================

  await HiveLocalStorage.instance.inicializar();

  // =============================================================
  // INICIALIZAR SUPABASE
  // =============================================================

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  // =============================================================
  // INICIALIZAR FIREBASE SOLO EN ANDROID
  // =============================================================
  // Por ahora FlutterFire se configuró únicamente para Android.
  // En Chrome y otras plataformas se mantiene RegiServ sin FCM.
  // Si falla Firebase, no bloqueamos las funciones de Supabase
  // ni el almacenamiento/sincronización local.
  // =============================================================

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      NotificacionesPushService.instance.iniciar();

      debugPrint('FIREBASE ANDROID INICIALIZADO.');
    } catch (error, stackTrace) {
      debugPrint('ERROR INICIALIZANDO FIREBASE ANDROID: $error');
      debugPrint('$stackTrace');
    }
  }

  runApp(const RegiServApp());
}

// =================================================================
// APLICACIÓN
// =================================================================

class RegiServApp extends StatefulWidget {
  const RegiServApp({super.key});

  @override
  State<RegiServApp> createState() => _RegiServAppState();
}

class _RegiServAppState extends State<RegiServApp> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  StreamSubscription<AuthState>? authSubscription;

  // Evita que la restauración normal interrumpa un enlace de
  // recuperación de contraseña recibido al abrir la app.
  bool _recuperacionEnProceso = false;

  late final SincronizacionAutomaticaService _sincronizacionAutomaticaService;

  @override
  void initState() {
    super.initState();

    _sincronizacionAutomaticaService = SincronizacionAutomaticaService(
      localStorage: HiveLocalStorage.instance,
      remoteBackend: SupabaseRemoteBackend(Supabase.instance.client),
    );

    _sincronizacionAutomaticaService.iniciar();

    authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        if (data.event == AuthChangeEvent.signedOut) {
          _recuperacionEnProceso = false;
          // Respaldo para cierres de sesión fuera de los tres Home.
          unawaited(
            NotificacionesPushService.instance.invalidarDespuesDeSalir(),
          );
        }

        if (data.event == AuthChangeEvent.passwordRecovery) {
          _recuperacionEnProceso = true;
          // El enlace de recuperación creó una sesión
          // temporal válida. Abrimos directamente la
          // pantalla para definir la nueva contraseña.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final navigator = navigatorKey.currentState;

            if (navigator == null) {
              return;
            }

            navigator.pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => const RestablecerContrasenaPage(),
              ),
              (route) => false,
            );
          });
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('ERROR EVENTO AUTH REGISERV: $error');
      },
    );
  }

  @override
  void dispose() {
    unawaited(_sincronizacionAutomaticaService.detener());

    authSubscription?.cancel();
    super.dispose();
  }

<<<<<<< HEAD
=======
  // This widget is the root of your application.ssa
>>>>>>> 0ead2a987c8eaf48b3d0ab5cd3594657150c5a60
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,

      title: 'RegiServ',

      theme: ThemeData(
        useMaterial3: true,

        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),

        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),

      // Solamente declaramos "/".
      // La ruta inicial verifica si Supabase conservó la sesión.
      // No modifica los destinos ni el proceso de login manual.
      routes: {
        '/': (context) => _EntradaRegiServPage(
          recuperacionEnProceso: () => _recuperacionEnProceso,
        ),
      },
    );
  }
}

// =================================================================
// INICIO AUTOMÁTICO DE SESIÓN
// =================================================================
// Supabase.initialize restaura la sesión persistida. RegiServ verifica
// en public.usuario que el funcionario siga activo, conserva los roles,
// y reconstruye los datos de SesionData antes de entrar a su Home.
// Si la red falla, NO elimina la sesión: permite reintentar.
// =================================================================

class _EntradaRegiServPage extends StatefulWidget {
  const _EntradaRegiServPage({required this.recuperacionEnProceso});

  final bool Function() recuperacionEnProceso;

  @override
  State<_EntradaRegiServPage> createState() => _EntradaRegiServPageState();
}

class _EntradaRegiServPageState extends State<_EntradaRegiServPage> {
  bool _comprobando = true;
  String? _mensajeError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_restaurarSesion());
      }
    });
  }

  void _abrir(Widget pantalla) {
    if (!mounted || widget.recuperacionEnProceso()) {
      return;
    }

    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => pantalla));
  }

  Future<void> _cerrarSesionRestaurada() async {
    final supabase = Supabase.instance.client;
    try {
      // Cierra únicamente la sesión de este dispositivo, no las
      // sesiones que el mismo funcionario tenga en otros teléfonos.
      await supabase.auth.signOut(scope: SignOutScope.local);
    } catch (error) {
      debugPrint('AVISO CIERRE SESIÓN RESTAURADA: $error');
    } finally {
      SesionData.cerrarSesion();
    }
  }

  Future<void> _actualizarCacheDelAuxiliar({required String idUsuario}) async {
    try {
      final servicio = CacheOperacionalService(
        localStorage: HiveLocalStorage.instance,
        remoteBackend: SupabaseRemoteBackend(Supabase.instance.client),
      );
      await servicio.actualizarCacheAuxiliar(idUsuario: idUsuario);
    } catch (error) {
      // El caché es auxiliar: una falla no impide iniciar sesión.
      debugPrint('NO SE PUDO ACTUALIZAR CACHE RESTAURADA: $error');
    }
  }

  Future<void> _restaurarSesion() async {
    if (!mounted) return;
    setState(() {
      _comprobando = true;
      _mensajeError = null;
    });

    final supabase = Supabase.instance.client;

    try {
      final sesion = supabase.auth.currentSession;
      final usuarioAuth = supabase.auth.currentUser;

      if (sesion == null || usuarioAuth == null) {
        SesionData.cerrarSesion();
        _abrir(const LoginPage());
        return;
      }

      final idUsuario = usuarioAuth.id;

      // No se otorga acceso basándose únicamente en el JWT guardado:
      // el perfil y el estado del funcionario se comprueban en Supabase.
      final Map<String, dynamic> perfil = await supabase
          .from('usuario')
          .select(
            'id_usuario, '
            'id_rol, '
            'id_estado_usuario, '
            'id_sede, '
            'p_nombre, '
            's_nombre, '
            'apellido_pater, '
            'apellido_mater, '
            'rut, '
            'dv, '
            'email, '
            'activo, '
            'primer_acceso, '
            'requiere_cambio_clave',
          )
          .eq('id_usuario', idUsuario)
          .single();

      if (!mounted || widget.recuperacionEnProceso()) return;

      // No abrir un perfil si la sesión cambió durante la consulta.
      if (supabase.auth.currentUser?.id != idUsuario) {
        SesionData.cerrarSesion();
        _abrir(const LoginPage());
        return;
      }

      if (perfil['activo'] != true) {
        await _cerrarSesionRestaurada();
        _abrir(
          const LoginPage(
            mensajeInicial: 'Tu cuenta se encuentra inactiva. Comunícate con el Supervisor Jefe.',
          ),
        );
        return;
      }

      final Map<String, dynamic> rolData = await supabase
          .from('rol')
          .select('nombre')
          .eq('id_rol', perfil['id_rol'])
          .single();

      if (!mounted || widget.recuperacionEnProceso()) return;
      if (supabase.auth.currentUser?.id != idUsuario) {
        SesionData.cerrarSesion();
        _abrir(const LoginPage());
        return;
      }

      final String rol = (rolData['nombre'] ?? '').toString();

      // El navegador web está reservado al Supervisor Jefe.
      // Android mantiene las cuatro pantallas y roles originales.
      if (kIsWeb && rol != 'Supervisor Jefe') {
        await _cerrarSesionRestaurada();
        _abrir(
          const LoginPage(
            mensajeInicial:
                'El panel web de RegiServ es exclusivo del Supervisor Jefe.',
          ),
        );
        return;
      }

      final Widget destino;
      switch (rol) {
        case 'Auxiliar':
          destino = _destinoAuxiliarConLabor(idUsuario);
          break;
        case 'Supervisor':
          destino = const SupervisorHomePage();
          break;
        case 'Supervisor Jefe':
          destino = kIsWeb
              ? const PanelWebSupervisorJefePage()
              : const SupervisorJefeHomePage();
          break;
        case 'Mantención':
          destino = const MantencionHomePage();
          break;
        default:
          await _cerrarSesionRestaurada();
          _abrir(
            const LoginPage(
              mensajeInicial: 'Tu cuenta no tiene un rol válido en RegiServ.',
            ),
          );
          return;
      }

      // La contraseña temporal debe cambiarse mediante el login
      // normal, porque CambiarContrasenaPage exige la clave actual.
      // Se impide acceder al Home sin completar esa obligación.
      final bool debeCambiarClave =
          perfil['primer_acceso'] == true ||
          perfil['requiere_cambio_clave'] == true;
      if (debeCambiarClave) {
        await _cerrarSesionRestaurada();
        _abrir(
          const LoginPage(
            mensajeInicial: 'Ingresa con tu contraseña inicial para completar el cambio obligatorio.',
          ),
        );
        return;
      }

      SesionData.iniciarSesionDesdeSupabase(perfil: perfil, rol: rol);

      if (rol == 'Auxiliar') {
        try {
          await HiveLocalStorage.instance.guardarPerfil(
            idUsuario: idUsuario,
            perfil: {...perfil, 'rol': rol},
          );
        } catch (error) {
          debugPrint('NO SE PUDO GUARDAR PERFIL RESTAURADO: $error');
        }
        unawaited(_actualizarCacheDelAuxiliar(idUsuario: idUsuario));
      }

      if (!mounted || widget.recuperacionEnProceso()) return;
      if (supabase.auth.currentUser?.id != idUsuario) return;

      // Igual que en el login manual: volver a registrar el teléfono
      // Android, sin bloquear el ingreso si FCM no está disponible.
      unawaited(
        NotificacionesPushService.instance.registrarAlIniciarSesion(rol: rol),
      );
      _abrir(destino);
    } catch (error) {
      if (!mounted || widget.recuperacionEnProceso()) return;
      // Un fallo de red no implica que el usuario haya cerrado sesión.
      // No eliminamos el token guardado ni entramos sin comprobar el rol.
      debugPrint('ERROR RESTAURANDO SESIÓN REGISERV: $error');
      setState(() {
        _comprobando = false;
        _mensajeError = 'No fue posible verificar tu sesión. Revisa tu conexión y vuelve a intentar.';
      });
    }
  }

  Future<void> _salirDeLaCuenta() async {
    if (!mounted) return;
    setState(() => _comprobando = true);
    await NotificacionesPushService.instance.retirarAntesCerrarSesion();
    await _cerrarSesionRestaurada();
    _abrir(const LoginPage());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _comprobando
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 20),
                        Text(
                          'Comprobando sesión de RegiServ...',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off_outlined, size: 44),
                        const SizedBox(height: 16),
                        Text(
                          _mensajeError ??
                              'No fue posible restaurar la sesión.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _restaurarSesion,
                            child: const Text('Reintentar'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _salirDeLaCuenta,
                          child: const Text(
                            'Cerrar sesión en este dispositivo',
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// =================================================================
// LOGIN
// =================================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.mensajeInicial});

  final String? mensajeInicial;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController correoController = TextEditingController();

  final TextEditingController contrasenaController = TextEditingController();

  bool ocultarContrasena = true;

  bool cargando = false;

  String? mensajeError;

  @override
  void initState() {
    super.initState();
    mensajeError = widget.mensajeInicial;
  }

  // =============================================================
  // CLIENTE SUPABASE
  // =============================================================

  SupabaseClient get supabase {
    return Supabase.instance.client;
  }

  @override
  void dispose() {
    correoController.dispose();
    contrasenaController.dispose();

    super.dispose();
  }

  // =============================================================
  // INICIAR SESIÓN
  // =============================================================

  Future<void> iniciarSesion() async {
    final correo = correoController.text.trim();

    final contrasena = contrasenaController.text;

    // -----------------------------------------------------------
    // VALIDAR CAMPOS
    // -----------------------------------------------------------

    if (correo.isEmpty || contrasena.isEmpty) {
      setState(() {
        mensajeError = 'Ingresa tu correo y contraseña.';
      });

      return;
    }

    setState(() {
      cargando = true;
      mensajeError = null;
    });

    try {
      // =========================================================
      // 1. AUTENTICACIÓN REAL EN SUPABASE AUTH
      // =========================================================

      final AuthResponse respuesta = await supabase.auth.signInWithPassword(
        email: correo,
        password: contrasena,
      );

      final User? authUser = respuesta.user;

      if (authUser == null) {
        throw Exception('AUTH_USER_NULL');
      }

      // =========================================================
      // 2. BUSCAR PERFIL EN public.usuario
      // =========================================================

      Map<String, dynamic> perfil = await supabase
          .from('usuario')
          .select(
            'id_usuario, '
            'id_rol, '
            'id_estado_usuario, '
            'id_sede, '
            'p_nombre, '
            's_nombre, '
            'apellido_pater, '
            'apellido_mater, '
            'rut, '
            'dv, '
            'email, '
            'activo, '
            'primer_acceso, '
            'requiere_cambio_clave',
          )
          .eq('id_usuario', authUser.id)
          .single();

      // =========================================================
      // 3. VALIDAR QUE ESTÉ ACTIVO EN REGISERV
      // =========================================================

      if (perfil['activo'] != true) {
        await supabase.auth.signOut();

        SesionData.cerrarSesion();

        throw Exception('USUARIO_INACTIVO');
      }

      // =========================================================
      // 4. OBTENER NOMBRE DEL ROL
      // =========================================================

      final Map<String, dynamic> rolData = await supabase
          .from('rol')
          .select('nombre')
          .eq('id_rol', perfil['id_rol'])
          .single();

      final String rol = rolData['nombre'].toString();

      // Un Auxiliar, Supervisor o Mantención no puede ingresar
      // a las pantallas administrativas desde el navegador.
      if (kIsWeb && rol != 'Supervisor Jefe') {
        await supabase.auth.signOut(scope: SignOutScope.local);
        SesionData.cerrarSesion();
        if (!mounted) return;
        setState(() {
          mensajeError =
              'El panel web de RegiServ es exclusivo del Supervisor Jefe.';
        });
        return;
      }

      // =========================================================
      // 5. GUARDAR SESIÓN DE REGISERV
      // =========================================================

      SesionData.iniciarSesionDesdeSupabase(perfil: perfil, rol: rol);

      if (!mounted) {
        return;
      }

      // =========================================================
      // 6. DEFINIR DESTINO SEGÚN ROL
      // =========================================================

      Widget destino;

      switch (rol) {
        case 'Auxiliar':
          destino = _destinoAuxiliarConLabor(authUser.id);
          break;

        case 'Supervisor':
          destino = const SupervisorHomePage();
          break;

        case 'Supervisor Jefe':
          destino = kIsWeb
              ? const PanelWebSupervisorJefePage()
              : const SupervisorJefeHomePage();
          break;

        case 'Mantención':
          destino = const MantencionHomePage();
          break;

        default:
          await supabase.auth.signOut();

          SesionData.cerrarSesion();

          throw Exception('ROL_NO_VALIDO');
      }

      // =========================================================
      // 7. CAMBIO OBLIGATORIO DE CONTRASEÑA
      // =========================================================
      //
      // Ningún usuario puede cambiar su contraseña libremente.
      // Esta pantalla solo se abre cuando la cuenta está marcada
      // como primer acceso / requiere cambio de clave.
      //
      // Se consideran ambos campos para mantener compatibilidad
      // con usuarios creados antes de agregar
      // requiere_cambio_clave.
      // =========================================================

      final bool requiereCambioClave =
          perfil['requiere_cambio_clave'] == true ||
          perfil['primer_acceso'] == true;

      if (requiereCambioClave) {
        if (!mounted) {
          return;
        }

        final bool? cambioRealizado = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) =>
                CambiarContrasenaPage(contrasenaActual: contrasena),
          ),
        );

        if (cambioRealizado != true) {
          // La pantalla obligatoria no permite volver atrás,
          // pero mantenemos esta protección adicional.
          await supabase.auth.signOut();

          SesionData.cerrarSesion();

          return;
        }

        // Recargamos el perfil después del cambio para que
        // SesionData también conserve el estado actualizado.
        final Map<String, dynamic> perfilActualizado = await supabase
            .from('usuario')
            .select(
              'id_usuario, '
              'id_rol, '
              'id_estado_usuario, '
              'id_sede, '
              'p_nombre, '
              's_nombre, '
              'apellido_pater, '
              'apellido_mater, '
              'rut, '
              'dv, '
              'email, '
              'activo, '
              'primer_acceso, '
              'requiere_cambio_clave',
            )
            .eq('id_usuario', authUser.id)
            .single();

        perfil = perfilActualizado;

        SesionData.iniciarSesionDesdeSupabase(
          perfil: perfilActualizado,
          rol: rol,
        );
      }

      if (!mounted) {
        return;
      }

      // =========================================================
      // 8. PREPARAR DATOS LOCALES DEL AUXILIAR
      // =========================================================
      //
      // Esta operación NO bloquea el ingreso:
      // si no hay conexión, se conserva la última caché válida.
      // =========================================================

      if (rol == 'Auxiliar') {
        try {
          await HiveLocalStorage.instance.guardarPerfil(
            idUsuario: authUser.id,
            perfil: {...perfil, 'rol': rol},
          );

          final CacheOperacionalService cacheService = CacheOperacionalService(
            localStorage: HiveLocalStorage.instance,
            remoteBackend: SupabaseRemoteBackend(supabase),
          );

          final bool cacheActualizada = await cacheService
              .actualizarCacheAuxiliar(idUsuario: authUser.id);

          debugPrint(
            cacheActualizada
                ? 'CACHE OFFLINE AUXILIAR ACTUALIZADA.'
                : 'CACHE OFFLINE AUXILIAR: se conserva la última copia válida.',
          );
        } catch (error) {
          debugPrint('ERROR PREPARANDO CACHE OFFLINE: $error');
        }
      }

      if (!mounted) {
        return;
      }

      // =========================================================
      // 9. ASOCIAR TOKEN ANDROID A LA CUENTA ACTUAL
      // =========================================================
      // No se ejecuta en Chrome. No bloquea el acceso si FCM falla.
      await NotificacionesPushService.instance.registrarAlIniciarSesion(
        rol: rol,
      );

      if (!mounted) {
        return;
      }

      // =========================================================
      // 10. ABRIR HOME
      // =========================================================

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => destino),
      );
    }
    // ===========================================================
    // ERROR DE AUTENTICACIÓN
    // ===========================================================
    on AuthException catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        mensajeError = 'Correo o contraseña incorrectos.';
      });
    }
    // ===========================================================
    // OTROS ERRORES
    // ===========================================================
    catch (error) {
      if (!mounted) {
        return;
      }

      final textoError = error.toString();

      setState(() {
        if (textoError.contains('USUARIO_INACTIVO')) {
          mensajeError = 'Tu cuenta se encuentra inactiva. Comunícate con el Supervisor Jefe.';
        } else if (textoError.contains('ROL_NO_VALIDO')) {
          mensajeError = 'Tu cuenta no tiene un rol válido en RegiServ.';
        } else {
          mensajeError = 'No fue posible iniciar sesión. Revisa la configuración o conexión con Supabase.';
        }
      });

      // Solo para desarrollo.
      debugPrint('ERROR LOGIN REGISERV: $error');
    } finally {
      if (mounted) {
        setState(() {
          cargando = false;
        });
      }
    }
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),

            child: Container(
              width: double.infinity,

              constraints: const BoxConstraints(maxWidth: 420),

              padding: const EdgeInsets.all(28),

              decoration: BoxDecoration(
                color: Colors.white,

                borderRadius: BorderRadius.circular(22),

                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),

                    blurRadius: 20,

                    offset: const Offset(0, 6),
                  ),
                ],
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,

                children: [
                  // =============================================
                  // LOGO
                  // =============================================

                  const Icon(
                    Icons.cleaning_services_outlined,

                    size: 54,

                    color: Color(0xFF1565C0),
                  ),

                  const SizedBox(height: 14),

                  const Text(
                    'RegiServ',

                    textAlign: TextAlign.center,

                    style: TextStyle(
                      fontSize: 30,

                      fontWeight: FontWeight.bold,

                      color: Color(0xFF1F2937),
                    ),
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    'Control y trazabilidad de labores de aseo',

                    textAlign: TextAlign.center,

                    style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                  ),

                  const SizedBox(height: 32),

                  // =============================================
                  // CORREO
                  // =============================================
                  TextField(
                    controller: correoController,

                    enabled: !cargando,

                    keyboardType: TextInputType.emailAddress,

                    decoration: InputDecoration(
                      labelText: 'Correo',

                      hintText: 'usuario@correo.cl',

                      prefixIcon: const Icon(Icons.email_outlined),

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // =============================================
                  // CONTRASEÑA
                  // =============================================
                  TextField(
                    controller: contrasenaController,

                    enabled: !cargando,

                    obscureText: ocultarContrasena,

                    decoration: InputDecoration(
                      labelText: 'Contraseña',

                      prefixIcon: const Icon(Icons.lock_outline),

                      suffixIcon: IconButton(
                        onPressed: cargando
                            ? null
                            : () {
                                setState(() {
                                  ocultarContrasena = !ocultarContrasena;
                                });
                              },

                        icon: Icon(
                          ocultarContrasena
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),

                    onSubmitted: (_) {
                      if (!cargando) {
                        iniciarSesion();
                      }
                    },
                  ),

                  // =============================================
                  // MENSAJE ERROR
                  // =============================================
                  if (mensajeError != null) ...[
                    const SizedBox(height: 14),

                    Container(
                      padding: const EdgeInsets.all(12),

                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),

                        borderRadius: BorderRadius.circular(10),

                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),

                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          const Icon(
                            Icons.error_outline,

                            color: Color(0xFFDC2626),

                            size: 19,
                          ),

                          const SizedBox(width: 8),

                          Expanded(
                            child: Text(
                              mensajeError!,

                              style: const TextStyle(
                                color: Color(0xFF991B1B),

                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),

                  // =============================================
                  // RECUPERAR CONTRASEÑA
                  // =============================================
                  Align(
                    alignment: Alignment.centerRight,

                    child: TextButton(
                      onPressed: cargando
                          ? null
                          : () {
                              Navigator.push(
                                context,

                                MaterialPageRoute(
                                  builder: (context) =>
                                      const RecuperarContrasenaPage(),
                                ),
                              );
                            },

                      child: const Text('¿Olvidaste tu contraseña?'),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // =============================================
                  // BOTÓN LOGIN
                  // =============================================
                  SizedBox(
                    height: 54,

                    child: ElevatedButton(
                      onPressed: cargando ? null : iniciarSesion,

                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),

                        foregroundColor: Colors.white,

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),

                      child: cargando
                          ? const SizedBox(
                              width: 22,

                              height: 22,

                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,

                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Iniciar sesión',

                              style: TextStyle(
                                fontSize: 16,

                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,

                    children: [
                      Icon(
                        Icons.verified_user_outlined,

                        size: 16,

                        color: Color(0xFF6B7280),
                      ),

                      SizedBox(width: 6),

                      Text(
                        'Autenticación segura con Supabase',

                        style: TextStyle(
                          fontSize: 12,

                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
