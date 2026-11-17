import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/labor/labor_context.dart';
import '../core/labor/labor_operacion_service.dart';
import '../core/remote/supabase_remote_backend.dart';
import '../core/storage/hive_local_storage.dart';

import 'registro_final_page.dart';
import 'registro_final_offline_page.dart';
import 'solicitar_cierre_excepcional_page.dart';

class ValidarTerminoPage extends StatefulWidget {
  final LaborContext labor;

  const ValidarTerminoPage({super.key, required this.labor});

  @override
  State<ValidarTerminoPage> createState() => _ValidarTerminoPageState();
}

class _ValidarTerminoPageState extends State<ValidarTerminoPage> {
  bool leyendoNfc = false;
  bool validandoGps = false;
  bool finalizandoLabor = false;

  bool nfcValidado = false;
  bool ubicacionValidada = false;

  String? uidNfcLeido;
  Position? posicionValidada;

  double? distanciaMetros;

  bool get esDispositivoMovil {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  double? get latitudEspacio => widget.labor.radioLatitud;

  double? get longitudEspacio => widget.labor.radioLongitud;

  double? get radioMetros => widget.labor.radioMetros;

  bool get puedeContinuar =>
      nfcValidado &&
      ubicacionValidada &&
      uidNfcLeido != null &&
      posicionValidada != null &&
      !finalizandoLabor;

  String normalizarUid(String valor) {
    return valor.trim().toUpperCase().replaceAll(RegExp(r'[\s:\-]'), '');
  }

  void mostrarMensaje(String mensaje, {bool error = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: error
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
        ),
      );
  }

  // =============================================================
  // NFC REAL DE TÉRMINO
  // =============================================================

  Future<void> validarNfc() async {
    if (!esDispositivoMovil) {
      mostrarMensaje(
        'La validación NFC real debe realizarse desde Android o iOS.',
        error: true,
      );
      return;
    }

    final String esperado = normalizarUid(widget.labor.uidNfcInicio);

    if (!RegExp(r'^[0-9A-F]{14}$').hasMatch(esperado)) {
      mostrarMensaje(
        'El NFC guardado en la labor no corresponde a un UID NTAG215 válido.',
        error: true,
      );
      return;
    }

    setState(() {
      leyendoNfc = true;
      nfcValidado = false;
      ubicacionValidada = false;
      uidNfcLeido = null;
      posicionValidada = null;
      distanciaMetros = null;
    });

    bool sesionActiva = false;

    try {
      final disponibilidad = await NfcManager.instance.checkAvailability();

      if (disponibilidad == NfcAvailability.unsupported) {
        throw Exception('Este teléfono no posee NFC.');
      }

      if (disponibilidad == NfcAvailability.disabled) {
        throw Exception('El NFC del teléfono está desactivado.');
      }

      final completer = Completer<String>();

      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        invalidateAfterFirstReadIos: true,
        alertMessageIos:
            'Acerca el iPhone al mismo NTAG215 utilizado al iniciar la labor.',
        onSessionErrorIos: (error) {
          sesionActiva = false;

          if (!completer.isCompleted) {
            completer.completeError(Exception('La lectura NFC fue cancelada.'));
          }
        },
        onDiscovered: (NfcTag tag) async {
          try {
            final String uid = obtenerUidTag(tag);

            final String leido = normalizarUid(uid);

            if (leido != esperado) {
              throw Exception(
                'Debes finalizar utilizando el mismo NFC con el que se inició la labor.',
              );
            }

            if (!completer.isCompleted) {
              completer.complete(leido);
            }

            try {
              await NfcManager.instance.stopSession(
                alertMessageIos: 'NFC de término validado.',
              );
            } catch (_) {}

            sesionActiva = false;
          } catch (error) {
            try {
              await NfcManager.instance.stopSession(
                errorMessageIos:
                    'El NFC no corresponde al utilizado al inicio.',
              );
            } catch (_) {}

            sesionActiva = false;

            if (!completer.isCompleted) {
              completer.completeError(error);
            }
          }
        },
      );

      sesionActiva = true;

      final String uid = await completer.future.timeout(
        const Duration(seconds: 45),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        uidNfcLeido = uid;
        nfcValidado = true;
      });

      mostrarMensaje('NFC de término validado correctamente.');
    } on TimeoutException {
      mostrarMensaje(
        'No se detectó una etiqueta NFC dentro del tiempo disponible.',
        error: true,
      );
    } catch (error) {
      debugPrint('ERROR VALIDANDO NFC DE TÉRMINO: $error');

      mostrarMensaje(
        error.toString().replaceFirst('Exception: ', ''),
        error: true,
      );
    } finally {
      if (sesionActiva) {
        try {
          await NfcManager.instance.stopSession();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          leyendoNfc = false;
        });
      }
    }
  }

  String obtenerUidTag(NfcTag tag) {
    List<int>? bytesUid;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final tagAndroid = NfcTagAndroid.from(tag);

      if (tagAndroid == null) {
        throw Exception('Android no pudo leer la identificación NFC.');
      }

      bytesUid = tagAndroid.id;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final tagIos = MiFareIos.from(tag);

      if (tagIos == null) {
        throw Exception('La etiqueta detectada no es compatible con NTAG215.');
      }

      bytesUid = tagIos.identifier;
    }

    if (bytesUid == null || bytesUid.isEmpty) {
      throw Exception('La etiqueta NFC no entregó un UID.');
    }

    if (bytesUid.length != 7) {
      throw Exception(
        'La etiqueta detectada tiene un UID de '
        '${bytesUid.length} bytes. '
        'Verifica que corresponda a un NTAG215.',
      );
    }

    return bytesUid
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
  }

  // =============================================================
  // GPS REAL DE TÉRMINO
  // =============================================================

  Future<void> validarUbicacion() async {
    if (!nfcValidado) {
      mostrarMensaje('Primero debes validar el NFC.', error: true);
      return;
    }

    if (!esDispositivoMovil) {
      mostrarMensaje(
        'La ubicación real debe validarse desde Android o iOS.',
        error: true,
      );
      return;
    }

    if (latitudEspacio == null ||
        longitudEspacio == null ||
        radioMetros == null ||
        radioMetros! <= 0) {
      mostrarMensaje(
        'La labor no posee una configuración GPS local válida.',
        error: true,
      );
      return;
    }

    setState(() {
      validandoGps = true;
      ubicacionValidada = false;
      posicionValidada = null;
      distanciaMetros = null;
    });

    try {
      final Position? posicion = await obtenerPosicionReal();

      if (posicion == null) {
        return;
      }

      final double distancia = Geolocator.distanceBetween(
        latitudEspacio!,
        longitudEspacio!,
        posicion.latitude,
        posicion.longitude,
      );

      if (!mounted) {
        return;
      }

      if (distancia > radioMetros!) {
        setState(() {
          distanciaMetros = distancia;
        });

        mostrarMensaje(
          'Estás a ${distancia.toStringAsFixed(1)} m del espacio. '
          'El radio permitido es de ${radioMetros!.toStringAsFixed(0)} m.',
          error: true,
        );

        return;
      }

      setState(() {
        posicionValidada = posicion;
        distanciaMetros = distancia;
        ubicacionValidada = true;
      });

      mostrarMensaje(
        'Ubicación de término validada. '
        'Distancia: ${distancia.toStringAsFixed(1)} m.',
      );
    } catch (error) {
      debugPrint('ERROR VALIDANDO GPS DE TÉRMINO: $error');

      mostrarMensaje(
        error.toString().replaceFirst('Exception: ', ''),
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          validandoGps = false;
        });
      }
    }
  }

  Future<Position?> obtenerPosicionReal() async {
    final bool servicioActivo = await Geolocator.isLocationServiceEnabled();

    if (!servicioActivo) {
      mostrarMensaje(
        'Activa la ubicación del teléfono para continuar.',
        error: true,
      );
      return null;
    }

    LocationPermission permiso = await Geolocator.checkPermission();

    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }

    if (permiso == LocationPermission.denied) {
      mostrarMensaje('Debes autorizar el acceso a la ubicación.', error: true);
      return null;
    }

    if (permiso == LocationPermission.deniedForever) {
      mostrarMensaje(
        'El permiso de ubicación está bloqueado. Habilítalo desde los ajustes de RegiServ.',
        error: true,
      );
      return null;
    }

    final precision = await Geolocator.getLocationAccuracy();

    if (precision == LocationAccuracyStatus.reduced) {
      mostrarMensaje('RegiServ necesita ubicación precisa.', error: true);
      return null;
    }

    const configuracion = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      timeLimit: Duration(seconds: 25),
    );

    return Geolocator.getCurrentPosition(locationSettings: configuracion);
  }

  // =============================================================
  // FINALIZAR LABOR ONLINE / OFFLINE
  // =============================================================

  Future<void> finalizarLabor() async {
    if (!puedeContinuar) {
      return;
    }

    final String? uid = uidNfcLeido;

    final Position? posicion = posicionValidada;

    if (uid == null || posicion == null) {
      return;
    }

    setState(() {
      finalizandoLabor = true;
    });

    try {
      final LaborOperacionService servicio = LaborOperacionService(
        localStorage: HiveLocalStorage.instance,
        remoteBackend: SupabaseRemoteBackend(Supabase.instance.client),
      );

      final LaborOperacionResultado resultado = await servicio.finalizarLabor(
        idUsuario: widget.labor.idUsuario,
        uidNfc: uid,
        latitudFin: posicion.latitude,
        longitudFin: posicion.longitude,
      );

      final LaborContext laborFinal = resultado.labor;

      final DateTime horaFin = (laborFinal.fechaHoraFin ?? DateTime.now())
          .toLocal();

      if (!mounted) {
        return;
      }

      // ---------------------------------------------------------
      // ONLINE: CONTINÚA AL FORMULARIO FINAL EXISTENTE
      // ---------------------------------------------------------

      if (!resultado.modoOffline && laborFinal.idRegistroRemoto != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => RegistroFinalPage(
              idRegistroAseo: laborFinal.idRegistroRemoto!,
              nombreAuxiliar: laborFinal.nombreAuxiliar,
              lugar: laborFinal.lugar,
              horaInicio: laborFinal.fechaHoraInicio.toLocal(),
              horaTermino: horaFin,
            ),
          ),
        );

        return;
      }

      // ---------------------------------------------------------
      // OFFLINE: TÉRMINO YA QUEDÓ GUARDADO EN HIVE
      // ---------------------------------------------------------

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => RegistroFinalOfflinePage(labor: laborFinal),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('ERROR FINALIZANDO LABOR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      String mensaje = error.toString();

      mensaje = mensaje
          .replaceFirst('Bad state: ', '')
          .replaceFirst('StateError: ', '')
          .replaceFirst('RemoteRejectedException: ', '')
          .replaceFirst('Exception: ', '');

      mostrarMensaje(mensaje, error: true);
    } finally {
      if (mounted) {
        setState(() {
          finalizandoLabor = false;
        });
      }
    }
  }

  void solicitarCierreExcepcional() {
    final int? idRemoto = widget.labor.idRegistroRemoto;

    if (idRemoto == null) {
      mostrarMensaje(
        'La solicitud de cierre excepcional requiere que la labor esté sincronizada con el servidor.',
        error: true,
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SolicitarCierreExcepcionalPage(
          nombreAuxiliar: widget.labor.nombreAuxiliar,
          lugar: widget.labor.lugar,
          horaInicio: widget.labor.fechaHoraInicio.toLocal(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: const Text(
            'Finalizar labor',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Lugar',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.labor.lugar,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Validación de término',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Debes leer nuevamente el mismo NFC utilizado al inicio y validar tu ubicación.',
                      style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    _PasoValidacion(
                      numero: '1',
                      titulo: 'Validar NFC de término',
                      descripcion: nfcValidado
                          ? 'El NFC corresponde al utilizado al inicio.'
                          : 'Acerca el teléfono al mismo NTAG215 utilizado al comenzar la labor.',
                      validado: nfcValidado,
                      cargando: leyendoNfc,
                      textoBoton: 'Leer NFC',
                      textoCargando: 'Esperando etiqueta...',
                      icono: Icons.nfc,
                      onPressed: nfcValidado || leyendoNfc ? null : validarNfc,
                    ),
                    const SizedBox(height: 16),
                    _PasoValidacion(
                      numero: '2',
                      titulo: 'Validar ubicación',
                      descripcion: ubicacionValidada
                          ? 'Ubicación correcta. Distancia: ${distanciaMetros?.toStringAsFixed(1) ?? '-'} m.'
                          : nfcValidado
                          ? 'Comprueba que estás dentro del radio permitido de ${radioMetros?.toStringAsFixed(0) ?? '-'} m.'
                          : 'Primero debes validar el NFC.',
                      validado: ubicacionValidada,
                      cargando: validandoGps,
                      textoBoton: 'Validar ubicación',
                      textoCargando: 'Obteniendo GPS...',
                      icono: Icons.my_location_outlined,
                      onPressed:
                          !nfcValidado || ubicacionValidada || validandoGps
                          ? null
                          : validarUbicacion,
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: puedeContinuar ? finalizarLabor : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFD1D5DB),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: finalizandoLabor
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Continuar',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: solicitarCierreExcepcional,
                        icon: const Icon(Icons.support_agent_outlined),
                        label: const Text('Solicitar cierre excepcional'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasoValidacion extends StatelessWidget {
  final String numero;
  final String titulo;
  final String descripcion;
  final bool validado;
  final bool cargando;
  final String textoBoton;
  final String textoCargando;
  final IconData icono;
  final VoidCallback? onPressed;

  const _PasoValidacion({
    required this.numero,
    required this.titulo,
    required this.descripcion,
    required this.validado,
    required this.cargando,
    required this.textoBoton,
    required this.textoCargando,
    required this.icono,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: validado ? const Color(0xFF86EFAC) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: validado
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFEFF6FF),
                  shape: BoxShape.circle,
                ),
                child: validado
                    ? const Icon(Icons.check, color: Color(0xFF16A34A))
                    : Text(
                        numero,
                        style: const TextStyle(
                          color: Color(0xFF1565C0),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Icon(icono, color: const Color(0xFF1565C0)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            descripcion,
            style: const TextStyle(color: Color(0xFF6B7280), height: 1.4),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: validado || cargando ? null : onPressed,
              icon: cargando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(validado ? Icons.check_circle_outline : icono),
              label: Text(
                validado
                    ? 'Validado'
                    : cargando
                    ? textoCargando
                    : textoBoton,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
