import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:geolocator/geolocator.dart';

import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/sesion_data.dart';
import 'labor_en_curso_page.dart';
import '../core/labor/labor_operacion_service.dart';
import '../core/remote/supabase_remote_backend.dart';
import '../core/storage/hive_local_storage.dart';
import '../widgets/confirmar_labor_no_asignada.dart';

class IniciarLaborPage extends StatefulWidget {
  final Map<String, dynamic>? labor;

  const IniciarLaborPage({super.key, this.labor});

  @override
  State<IniciarLaborPage> createState() => _IniciarLaborPageState();
}

class _IniciarLaborPageState extends State<IniciarLaborPage> {
  SupabaseClient get supabase => Supabase.instance.client;

  // =============================================================
  // ESTADO GENERAL
  // =============================================================

  bool cargando = true;

  bool leyendoNfc = false;
  bool validandoGps = false;
  bool iniciandoLabor = false;

  bool nfcValidado = false;
  bool ubicacionValidada = false;

  String? mensajeError;

  String? uidNfcEsperado;
  String? uidNfcLeido;

  Position? posicionValidada;

  double? distanciaMetros;

  double? latitudEspacio;
  double? longitudEspacio;

  int radioMetros = 30;

  // =============================================================
  // DATOS DE LA LABOR
  // =============================================================

  Map<String, dynamic>? laborCoberturaIdentificada;

  bool get esCobertura => widget.labor?['esCobertura'] == true;

  Map<String, dynamic>? get laborActual =>
      laborCoberturaIdentificada ?? widget.labor;

  int? get idEspacio => aInt(laborActual?['idEspacio']);

  String get codigoEspacio =>
      texto(laborActual?['codigoEspacio'], defecto: '-');

  String get nombreEspacio =>
      texto(laborActual?['nombreEspacio'], defecto: 'Espacio');

  String get tipoEspacio =>
      texto(laborActual?['tipoEspacio'], defecto: 'Espacio');

  String get nombreEdificio =>
      texto(laborActual?['nombreEdificio'], defecto: 'Edificio');

  int get numeroPiso => aInt(laborActual?['numeroPiso']) ?? 0;

  bool get esDispositivoMovil {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get puedeIniciar =>
      !cargando &&
      !iniciandoLabor &&
      nfcValidado &&
      ubicacionValidada &&
      uidNfcLeido != null &&
      posicionValidada != null;

  // =============================================================
  // INICIALIZACIÓN
  // =============================================================

  @override
  void initState() {
    super.initState();

    if (esCobertura) {
      // En cobertura se identifica el espacio leyendo primero su NFC.
      cargando = false;
    } else {
      cargarConfiguracionReal();
    }
  }

  // =============================================================
  // CONVERSIONES
  // =============================================================

  int? aInt(dynamic valor) {
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

  double? aDouble(dynamic valor) {
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

  String texto(dynamic valor, {String defecto = ''}) {
    if (valor == null) {
      return defecto;
    }

    final resultado = valor.toString().trim();

    if (resultado.isEmpty) {
      return defecto;
    }

    return resultado;
  }

  String normalizarUid(String valor) {
    return valor.trim().toUpperCase().replaceAll(RegExp(r'[\s:\-]'), '');
  }

  // =============================================================
  // MENSAJES
  // =============================================================

  void mostrarMensaje(String mensaje, {bool error = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error
            ? const Color(0xFFDC2626)
            : const Color(0xFF16A34A),
      ),
    );
  }

  // =============================================================
  // CARGAR CONFIGURACIÓN REAL
  // =============================================================

  Future<void> cargarConfiguracionReal() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;

        nfcValidado = false;
        ubicacionValidada = false;

        uidNfcLeido = null;
        posicionValidada = null;
        distanciaMetros = null;
      });
    }

    try {
      final id = idEspacio;

      if (laborActual == null || id == null) {
        throw Exception('No se recibió una labor seleccionada.');
      }

      final usuario = supabase.auth.currentUser;

      if (usuario == null) {
        throw Exception('No existe una sesión autenticada.');
      }

      // ---------------------------------------------------------
      // VERIFICAR ASIGNACIÓN VIGENTE
      // ---------------------------------------------------------

      final asignaciones = await supabase
          .from('espacio_trabajador')
          .select(
            'id_espacio, '
            'fecha_ini, '
            'fecha_ter',
          )
          .eq('id_usuario', usuario.id)
          .eq('id_espacio', id)
          .isFilter('fecha_ter', null);

      if (asignaciones.isEmpty) {
        throw Exception('Esta labor ya no está asignada al usuario.');
      }

      // ---------------------------------------------------------
      // ESPACIO
      // ---------------------------------------------------------

      final espacioData = await supabase
          .from('espacio')
          .select(
            'id_espacio, '
            'codigo, '
            'nombre, '
            'radio_latitud, '
            'radio_longitud, '
            'radio_metros, '
            'activo',
          )
          .eq('id_espacio', id)
          .single();

      if (espacioData['activo'] != true) {
        throw Exception('El espacio seleccionado está inactivo.');
      }

      final lat = aDouble(espacioData['radio_latitud']);

      final lon = aDouble(espacioData['radio_longitud']);

      final radio = aInt(espacioData['radio_metros']) ?? 30;

      if (lat == null || lon == null) {
        throw Exception('El espacio no tiene GPS configurado.');
      }

      // ---------------------------------------------------------
      // ESTADOS NFC OPERATIVOS
      // ---------------------------------------------------------

      final estadosData = await supabase
          .from('estado_nfc')
          .select(
            'id_estado_nfc, '
            'activo',
          );

      final Set<String> estadosOperativos = {};

      for (final fila in estadosData) {
        if (fila['activo'] == true) {
          estadosOperativos.add(fila['id_estado_nfc'].toString());
        }
      }

      // ---------------------------------------------------------
      // NFC VIGENTE DEL ESPACIO
      // ---------------------------------------------------------

      final nfcData = await supabase
          .from('nfc')
          .select(
            'id_nfc, '
            'id_estado_nfc, '
            'uid_nfc, '
            'fecha_retiro',
          )
          .eq('id_espacio', id)
          .isFilter('fecha_retiro', null);

      Map<String, dynamic>? nfcActiva;

      for (final fila in nfcData) {
        final nfc = Map<String, dynamic>.from(fila);

        if (estadosOperativos.contains(nfc['id_estado_nfc'].toString())) {
          nfcActiva = nfc;
          break;
        }
      }

      if (nfcActiva == null) {
        throw Exception('El espacio no tiene una NFC operativa.');
      }

      final uid = texto(nfcActiva['uid_nfc']);

      if (uid.isEmpty) {
        throw Exception('La NFC configurada no tiene UID.');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        latitudEspacio = lat;
        longitudEspacio = lon;

        radioMetros = radio;

        uidNfcEsperado = normalizarUid(uid);

        cargando = false;
      });
    } catch (error) {
      debugPrint(
        'ERROR CARGANDO LABOR: '
        '$error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;

        mensajeError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // =============================================================
  // VALIDAR NFC REAL
  // =============================================================

  Future<void> validarNfc() async {
    if (!esDispositivoMovil) {
      mostrarMensaje(
        'La validación NFC real debe realizarse desde Android o iOS.',
        error: true,
      );

      return;
    }

    if (!esCobertura && uidNfcEsperado == null) {
      mostrarMensaje(
        'No existe una NFC configurada para esta labor.',
        error: true,
      );

      return;
    }

    // Detecta configuraciones antiguas simuladas.
    if (!esCobertura && !RegExp(r'^[0-9A-F]{14}$').hasMatch(uidNfcEsperado!)) {
      mostrarMensaje(
        'Este espacio todavía tiene una NFC de prueba. '
        'El Supervisor Jefe debe reemplazarla leyendo el NTAG215 físico.',
        error: true,
      );

      return;
    }

    if (mounted) {
      setState(() {
        leyendoNfc = true;

        nfcValidado = false;
        ubicacionValidada = false;

        uidNfcLeido = null;
        posicionValidada = null;
        distanciaMetros = null;
      });
    }

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
            'Acerca el iPhone al NTAG215 del espacio $codigoEspacio.',

        onSessionErrorIos: (error) {
          sesionActiva = false;

          if (!completer.isCompleted) {
            completer.completeError(Exception('La lectura NFC fue cancelada.'));
          }
        },

        onDiscovered: (NfcTag tag) async {
          try {
            final uid = obtenerUidTag(tag);

            final leido = normalizarUid(uid);

            if (!esCobertura && leido != normalizarUid(uidNfcEsperado!)) {
              throw Exception(
                'La etiqueta NFC leída no corresponde al espacio $codigoEspacio.',
              );
            }

            if (!completer.isCompleted) {
              completer.complete(leido);
            }

            try {
              await NfcManager.instance.stopSession(
                alertMessageIos: 'NFC validado correctamente.',
              );
            } catch (_) {}

            sesionActiva = false;
          } catch (error) {
            try {
              await NfcManager.instance.stopSession(
                errorMessageIos: 'La etiqueta no corresponde a este espacio.',
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

      final uid = await completer.future.timeout(const Duration(seconds: 45));

      if (!mounted) {
        return;
      }

      if (esCobertura) {
        // El servidor resuelve a qué espacio pertenece la etiqueta,
        // sin consultar las asignaciones ni NFC de otros usuarios desde Flutter.
        final dynamic respuesta = await supabase.rpc(
          'identificar_espacio_cobertura',
          params: <String, dynamic>{'p_uid_nfc': uid},
        );
        if (respuesta is! Map) {
          throw Exception('No se pudo identificar el espacio por NFC.');
        }
        final Map<String, dynamic> espacio = Map<String, dynamic>.from(
          respuesta,
        );
        if (espacio['ok'] != true) {
          throw Exception('No fue posible reconocer el espacio.');
        }
        if (!mounted) return;
        final bool continuar = await confirmarLaborNoAsignada(
          context,
          nombreEspacio: espacio['nombreEspacio']?.toString(),
        );
        if (!mounted) return;
        if (!continuar) return;

        final double? lat = aDouble(espacio['radio_latitud']);
        final double? lon = aDouble(espacio['radio_longitud']);
        final int? radio = aInt(espacio['radio_metros']);
        if (lat == null || lon == null || radio == null || radio <= 0) {
          throw Exception('El espacio no tiene GPS configurado correctamente.');
        }
        setState(() {
          laborCoberturaIdentificada = <String, dynamic>{
            'esCobertura': true,
            ...espacio,
            'idEspacio': espacio['id_espacio'],
          };
          latitudEspacio = lat;
          longitudEspacio = lon;
          radioMetros = radio;
          uidNfcEsperado = normalizarUid(uid);
          uidNfcLeido = uid;
          nfcValidado = true;
          mensajeError = null;
        });
      } else {
        setState(() {
          uidNfcLeido = uid;
          nfcValidado = true;
        });
      }

      mostrarMensaje('NFC de $codigoEspacio validado correctamente.');
    } on TimeoutException {
      mostrarMensaje(
        'No se detectó una etiqueta NFC dentro del tiempo disponible.',
        error: true,
      );
    } catch (error) {
      debugPrint(
        'ERROR VALIDANDO NFC: '
        '$error',
      );

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

  // =============================================================
  // OBTENER UID DEL NTAG215
  // =============================================================

  String obtenerUidTag(NfcTag tag) {
    List<int>? bytesUid;

    // ---------------------------------------------------------
    // ANDROID
    // ---------------------------------------------------------

    if (defaultTargetPlatform == TargetPlatform.android) {
      final tagAndroid = NfcTagAndroid.from(tag);

      if (tagAndroid == null) {
        throw Exception('Android no pudo leer la identificación NFC.');
      }

      bytesUid = tagAndroid.id;
    }

    // ---------------------------------------------------------
    // IOS
    // ---------------------------------------------------------

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
  // VALIDAR GPS REAL
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

    if (latitudEspacio == null || longitudEspacio == null) {
      mostrarMensaje(
        'El espacio no tiene coordenadas configuradas.',
        error: true,
      );

      return;
    }

    if (mounted) {
      setState(() {
        validandoGps = true;

        ubicacionValidada = false;

        posicionValidada = null;
        distanciaMetros = null;
      });
    }

    try {
      final posicion = await obtenerPosicionReal();

      if (posicion == null) {
        return;
      }

      final distancia = Geolocator.distanceBetween(
        latitudEspacio!,
        longitudEspacio!,
        posicion.latitude,
        posicion.longitude,
      );

      if (!mounted) {
        return;
      }

      if (distancia > radioMetros) {
        setState(() {
          distanciaMetros = distancia;
        });

        mostrarMensaje(
          'Estás a ${distancia.toStringAsFixed(1)} m de $codigoEspacio. '
          'El radio permitido es de $radioMetros m.',
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
        'Ubicación validada. '
        'Distancia: ${distancia.toStringAsFixed(1)} m.',
      );
    } catch (error) {
      debugPrint(
        'ERROR VALIDANDO GPS: '
        '$error',
      );

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

  // =============================================================
  // OBTENER POSICIÓN REAL
  // =============================================================

  Future<Position?> obtenerPosicionReal() async {
    final servicioActivo = await Geolocator.isLocationServiceEnabled();

    if (!servicioActivo) {
      if (!mounted) {
        return null;
      }

      final abrir = await showDialog<bool>(
        context: context,

        builder: (context) {
          return AlertDialog(
            title: const Text('Ubicación desactivada'),

            content: const Text(
              'Activa la ubicación del teléfono para continuar.',
            ),

            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context, false);
                },

                child: const Text('Cancelar'),
              ),

              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, true);
                },

                child: const Text('Abrir ajustes'),
              ),
            ],
          );
        },
      );

      if (abrir == true) {
        await Geolocator.openLocationSettings();
      }

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
      if (!mounted) {
        return null;
      }

      final abrir = await showDialog<bool>(
        context: context,

        builder: (context) {
          return AlertDialog(
            title: const Text('Permiso bloqueado'),

            content: const Text(
              'El permiso de ubicación está bloqueado. '
              'Debes habilitarlo desde los ajustes de RegiServ.',
            ),

            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context, false);
                },

                child: const Text('Cancelar'),
              ),

              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, true);
                },

                child: const Text('Abrir ajustes'),
              ),
            ],
          );
        },
      );

      if (abrir == true) {
        await Geolocator.openAppSettings();
      }

      return null;
    }

    final precision = await Geolocator.getLocationAccuracy();

    if (precision == LocationAccuracyStatus.reduced) {
      mostrarMensaje(
        'RegiServ necesita ubicación precisa. '
        'Actívala en los permisos de la aplicación.',
        error: true,
      );

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
  // INICIAR LABOR REAL
  // =============================================================

  Future<void> comenzarLabor() async {
    if (iniciandoLabor) {
      return;
    }

    final usuarioAuth = Supabase.instance.client.auth.currentUser;

    if (usuarioAuth == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No existe una sesión activa.')),
        );

      return;
    }

    if (idEspacio == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No fue posible identificar el espacio.'),
          ),
        );

      return;
    }

    final String uid = (uidNfcLeido ?? '').trim();

    if (uid.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Debes validar el NFC antes de iniciar.'),
          ),
        );

      return;
    }

    final Position? posicion = posicionValidada;

    if (posicion == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Debes validar tu ubicación antes de iniciar.'),
          ),
        );

      return;
    }

    setState(() {
      iniciandoLabor = true;
    });

    try {
      final Map<String, dynamic> datosLabor =
          laborActual ?? <String, dynamic>{};

      final String nombreEspacio =
          (datosLabor['nombreEspacio'] ??
                  datosLabor['nombre_espacio'] ??
                  datosLabor['nombre'] ??
                  '')
              .toString()
              .trim();

      final String codigoEspacio =
          (datosLabor['codigoEspacio'] ??
                  datosLabor['codigo_espacio'] ??
                  datosLabor['codigo'] ??
                  '')
              .toString()
              .trim();

      final String nombreEdificio =
          (datosLabor['nombreEdificio'] ?? datosLabor['nombre_edificio'] ?? '')
              .toString()
              .trim();

      final dynamic pisoRaw =
          datosLabor['numeroPiso'] ??
          datosLabor['numero_piso'] ??
          datosLabor['numero_nivel'];

      final String numeroPiso = pisoRaw == null
          ? ''
          : pisoRaw.toString().trim();

      final List<String> partesLugar = <String>[
        if (nombreEspacio.isNotEmpty) nombreEspacio,
        if (codigoEspacio.isNotEmpty && codigoEspacio != nombreEspacio)
          codigoEspacio,
        if (nombreEdificio.isNotEmpty) nombreEdificio,
        if (numeroPiso.isNotEmpty) 'Piso $numeroPiso',
      ];

      final String lugar = partesLugar.isEmpty
          ? 'Espacio $idEspacio'
          : partesLugar.join(' · ');

      final String nombreAuxiliar = SesionData.nombreActual.trim().isNotEmpty
          ? SesionData.nombreActual
          : SesionData.primerNombreActual;

      final LaborOperacionService servicio = LaborOperacionService(
        localStorage: HiveLocalStorage.instance,
        remoteBackend: SupabaseRemoteBackend(Supabase.instance.client),
      );

      final LaborOperacionResultado resultado = await servicio.iniciarLabor(
        idUsuario: usuarioAuth.id,
        idEspacio: idEspacio!,
        uidNfc: uid,
        latitudInicio: posicion.latitude,
        longitudInicio: posicion.longitude,
        lugar: lugar,
        nombreAuxiliar: nombreAuxiliar,
        esCobertura: esCobertura,
        radioLatitudCobertura: latitudEspacio,
        radioLongitudCobertura: longitudEspacio,
        radioMetrosCobertura: radioMetros.toDouble(),
        idNfcCobertura: aInt(laborActual?['id_nfc']),
      );

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => LaborEnCursoPage(labor: resultado.labor),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('ERROR comenzarLabor: $error');
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

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(mensaje),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          iniciandoLabor = false;
        });
      }
    }
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),

        appBar: AppBar(
          backgroundColor: Colors.white,

          title: const Text('Iniciar labor'),
        ),

        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (mensajeError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),

        appBar: AppBar(
          backgroundColor: Colors.white,

          title: const Text('Iniciar labor'),
        ),

        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30),

            child: Column(
              mainAxisSize: MainAxisSize.min,

              children: [
                const Icon(
                  Icons.error_outline,

                  size: 56,

                  color: Color(0xFFDC2626),
                ),

                const SizedBox(height: 14),

                Text(mensajeError!, textAlign: TextAlign.center),

                const SizedBox(height: 18),

                ElevatedButton.icon(
                  onPressed: cargarConfiguracionReal,

                  icon: const Icon(Icons.refresh),

                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,

        surfaceTintColor: Colors.white,

        elevation: 0,

        title: const Text(
          'Iniciar labor',

          style: TextStyle(
            fontWeight: FontWeight.bold,

            color: Color(0xFF1F2937),
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),

          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 650),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  // =================================================
                  // LABOR SELECCIONADA
                  // =================================================

                  Text(
                    esCobertura && !nfcValidado
                        ? 'Identificar espacio por NFC'
                        : 'Labor seleccionada',

                    style: TextStyle(
                      fontSize: 26,

                      fontWeight: FontWeight.bold,

                      color: Color(0xFF1F2937),
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Antes de comenzar, RegiServ debe comprobar que estás físicamente en el espacio seleccionado.',

                    style: TextStyle(
                      fontSize: 15,

                      height: 1.4,

                      color: Color(0xFF6B7280),
                    ),
                  ),

                  const SizedBox(height: 22),

                  if (!esCobertura || laborCoberturaIdentificada != null)
                    _TarjetaEspacioSeleccionado(
                      nombre: nombreEspacio,

                      codigo: codigoEspacio,

                      tipo: tipoEspacio,

                      edificio: nombreEdificio,

                      piso: numeroPiso,

                      radio: radioMetros,
                    ),

                  const SizedBox(height: 20),

                  // =================================================
                  // NFC
                  // =================================================
                  _TarjetaValidacion(
                    numero: '1',

                    titulo: 'Validar NFC',

                    descripcion: nfcValidado
                        ? 'La etiqueta corresponde a $codigoEspacio.'
                        : esCobertura && laborCoberturaIdentificada == null
                        ? 'Acerca el teléfono al NFC del espacio que vas a cubrir.'
                        : 'Acerca el teléfono al NTAG215 instalado en $codigoEspacio.',

                    icono: Icons.nfc,

                    completado: nfcValidado,

                    procesando: leyendoNfc,

                    botonTexto: nfcValidado ? 'NFC validado' : 'Leer NFC',

                    textoProcesando: 'Esperando etiqueta...',

                    onPressed: nfcValidado || leyendoNfc ? null : validarNfc,
                  ),

                  const SizedBox(height: 16),

                  // =================================================
                  // GPS
                  // =================================================
                  _TarjetaValidacion(
                    numero: '2',

                    titulo: 'Validar ubicación',

                    descripcion: ubicacionValidada
                        ? 'Ubicación correcta. '
                              'Estás a ${distanciaMetros?.toStringAsFixed(1) ?? '-'} m del punto configurado.'
                        : nfcValidado
                        ? 'Comprueba que estás dentro del radio permitido de $radioMetros m.'
                        : 'Primero debes validar el NFC del espacio.',

                    icono: Icons.location_on_outlined,

                    completado: ubicacionValidada,

                    procesando: validandoGps,

                    botonTexto: ubicacionValidada
                        ? 'Ubicación validada'
                        : 'Validar ubicación',

                    textoProcesando: 'Obteniendo GPS...',

                    onPressed: !nfcValidado || ubicacionValidada || validandoGps
                        ? null
                        : validarUbicacion,
                  ),

                  if (distanciaMetros != null) ...[
                    const SizedBox(height: 14),

                    Container(
                      width: double.infinity,

                      padding: const EdgeInsets.all(14),

                      decoration: BoxDecoration(
                        color: ubicacionValidada
                            ? const Color(0xFFF0FDF4)
                            : const Color(0xFFFFF7ED),

                        borderRadius: BorderRadius.circular(12),
                      ),

                      child: Text(
                        'Distancia calculada: '
                        '${distanciaMetros!.toStringAsFixed(1)} m · '
                        'Radio permitido: $radioMetros m',

                        style: TextStyle(
                          fontWeight: FontWeight.w600,

                          color: ubicacionValidada
                              ? const Color(0xFF166534)
                              : const Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],

                  if (!esDispositivoMovil) ...[
                    const SizedBox(height: 16),

                    Container(
                      width: double.infinity,

                      padding: const EdgeInsets.all(14),

                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),

                        borderRadius: BorderRadius.circular(12),
                      ),

                      child: const Text(
                        'NFC y GPS reales requieren ejecutar RegiServ en Android o iOS. '
                        'Desde navegador puedes revisar la pantalla, pero no iniciar físicamente la labor.',

                        style: TextStyle(color: Color(0xFF92400E), height: 1.4),
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // =================================================
                  // COMENZAR
                  // =================================================
                  SizedBox(
                    width: double.infinity,

                    height: 56,

                    child: ElevatedButton.icon(
                      onPressed: puedeIniciar ? comenzarLabor : null,

                      icon: iniciandoLabor
                          ? const SizedBox(
                              width: 20,

                              height: 20,

                              child: CircularProgressIndicator(
                                strokeWidth: 2,

                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.play_arrow),

                      label: Text(
                        iniciandoLabor
                            ? 'Iniciando labor...'
                            : 'Comenzar labor',

                        style: const TextStyle(
                          fontSize: 16,

                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),

                        foregroundColor: Colors.white,

                        disabledBackgroundColor: const Color(0xFFD1D5DB),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
// LABOR SELECCIONADA
// =================================================================

class _TarjetaEspacioSeleccionado extends StatelessWidget {
  final String nombre;
  final String codigo;
  final String tipo;
  final String edificio;

  final int piso;
  final int radio;

  const _TarjetaEspacioSeleccionado({
    required this.nombre,
    required this.codigo,
    required this.tipo,
    required this.edificio,
    required this.piso,
    required this.radio,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Container(
                width: 50,

                height: 50,

                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),

                  borderRadius: BorderRadius.circular(13),
                ),

                child: const Icon(
                  Icons.cleaning_services_outlined,

                  color: Color(0xFF1565C0),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      nombre,

                      style: const TextStyle(
                        fontSize: 19,

                        fontWeight: FontWeight.bold,

                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      '$tipo · $codigo',

                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          const Divider(),

          const SizedBox(height: 12),

          _DatoEspacio(etiqueta: 'Edificio', valor: edificio),

          _DatoEspacio(etiqueta: 'Piso', valor: piso.toString()),

          _DatoEspacio(etiqueta: 'Radio GPS', valor: '$radio m'),

          _DatoEspacio(etiqueta: 'Auxiliar', valor: SesionData.nombreActual),
        ],
      ),
    );
  }
}

// =================================================================
// TARJETA VALIDACIÓN
// =================================================================

class _TarjetaValidacion extends StatelessWidget {
  final String numero;
  final String titulo;
  final String descripcion;

  final IconData icono;

  final bool completado;
  final bool procesando;

  final String botonTexto;
  final String textoProcesando;

  final VoidCallback? onPressed;

  const _TarjetaValidacion({
    required this.numero,
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.completado,
    required this.procesando,
    required this.botonTexto,
    required this.textoProcesando,
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
          color: completado ? const Color(0xFF86EFAC) : const Color(0xFFE5E7EB),
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
                  color: completado
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFEFF6FF),

                  shape: BoxShape.circle,
                ),

                child: completado
                    ? const Icon(
                        Icons.check,

                        color: Color(0xFF16A34A),

                        size: 20,
                      )
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

                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Text(
            descripcion,

            style: const TextStyle(
              fontSize: 14,

              height: 1.4,

              color: Color(0xFF6B7280),
            ),
          ),

          const SizedBox(height: 18),

          if (completado)
            Container(
              width: double.infinity,

              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),

              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),

                borderRadius: BorderRadius.circular(10),

                border: Border.all(color: const Color(0xFF86EFAC)),
              ),

              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,

                children: [
                  const Icon(
                    Icons.check_circle_outline,

                    color: Color(0xFF16A34A),

                    size: 20,
                  ),

                  const SizedBox(width: 8),

                  Text(
                    botonTexto,

                    style: const TextStyle(
                      color: Color(0xFF166534),

                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,

              child: OutlinedButton.icon(
                onPressed: procesando ? null : onPressed,

                icon: procesando
                    ? const SizedBox(
                        width: 18,

                        height: 18,

                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(icono),

                label: Text(procesando ? textoProcesando : botonTexto),

                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =================================================================
// DATO ESPACIO
// =================================================================

class _DatoEspacio extends StatelessWidget {
  final String etiqueta;
  final String valor;

  const _DatoEspacio({required this.etiqueta, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          SizedBox(
            width: 105,

            child: Text(
              etiqueta,

              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          ),

          Expanded(
            child: Text(
              valor,

              style: const TextStyle(
                fontWeight: FontWeight.w600,

                color: Color(0xFF1F2937),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
