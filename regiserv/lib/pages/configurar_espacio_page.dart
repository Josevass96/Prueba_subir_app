import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:geolocator/geolocator.dart';

import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class ConfigurarEspacioPage extends StatefulWidget {
  final Map<String, dynamic> espacio;

  const ConfigurarEspacioPage({super.key, required this.espacio});

  @override
  State<ConfigurarEspacioPage> createState() => _ConfigurarEspacioPageState();
}

class _ConfigurarEspacioPageState extends State<ConfigurarEspacioPage> {
  SupabaseClient get supabase => Supabase.instance.client;

  late Map<String, dynamic> espacio;

  bool cargando = true;

  bool guardandoGps = false;
  bool guardandoNfc = false;

  String? mensajeError;
  String? mensajeProcesoNfc;

  // =============================================================
  // INICIALIZACIÓN
  // =============================================================

  @override
  void initState() {
    super.initState();

    espacio = Map<String, dynamic>.from(widget.espacio);

    cargarConfiguracion();
  }

  // =============================================================
  // PLATAFORMA
  // =============================================================

  bool get esDispositivoMovil {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  // =============================================================
  // ESTADOS
  // =============================================================

  bool get gpsConfigurado =>
      espacio['radio_latitud'] != null && espacio['radio_longitud'] != null;

  bool get nfcConfigurado => espacio['nfcConfigurado'] == true;

  bool get configuracionCompleta => gpsConfigurado && nfcConfigurado;

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

  Future<void> cargarConfiguracion() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;
      });
    }

    try {
      final idEspacio = espacio['id_espacio'];

      if (idEspacio == null) {
        throw Exception('El espacio no contiene id_espacio.');
      }

      // ---------------------------------------------------------
      // ESPACIO
      // ---------------------------------------------------------

      final espacioData = await supabase
          .from('espacio')
          .select(
            'id_espacio, '
            'radio_latitud, '
            'radio_longitud, '
            'radio_metros, '
            'activo',
          )
          .eq('id_espacio', idEspacio)
          .single();

      // ---------------------------------------------------------
      // ESTADOS NFC OPERATIVOS
      // ---------------------------------------------------------

      final estadosNfcData = await supabase
          .from('estado_nfc')
          .select(
            'id_estado_nfc, '
            'activo',
          );

      final Set<String> estadosOperativos = {};

      for (final fila in estadosNfcData) {
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
            'fecha_instalacion, '
            'fecha_retiro',
          )
          .eq('id_espacio', idEspacio)
          .isFilter('fecha_retiro', null);

      Map<String, dynamic>? nfcActiva;

      for (final fila in nfcData) {
        final nfc = Map<String, dynamic>.from(fila);

        if (estadosOperativos.contains(nfc['id_estado_nfc'].toString())) {
          nfcActiva = nfc;
          break;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        espacio = {
          ...espacio,

          'radio_latitud': espacioData['radio_latitud'],

          'radio_longitud': espacioData['radio_longitud'],

          'radio_metros': espacioData['radio_metros'] ?? 30,

          'activo': espacioData['activo'],

          'nfcConfigurado': nfcActiva != null,

          'nfcUid': nfcActiva?['uid_nfc']?.toString(),

          'id_nfc': nfcActiva?['id_nfc'],
        };

        cargando = false;
      });
    } catch (error) {
      debugPrint(
        'ERROR CARGANDO CONFIGURACIÓN: '
        '$error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;

        mensajeError = 'No fue posible cargar la configuración del espacio.';
      });
    }
  }

  // =============================================================
  // GPS REAL
  // =============================================================

  Future<void> registrarGps() async {
    if (!esDispositivoMovil) {
      mostrarMensaje(
        'La ubicación física debe registrarse desde Android o iOS.',
        error: true,
      );

      return;
    }

    setState(() {
      guardandoGps = true;
    });

    try {
      final posicion = await obtenerPosicionReal();

      if (posicion == null || !mounted) {
        return;
      }

      final radio = await confirmarUbicacionGps(posicion);

      if (radio == null) {
        return;
      }

      await supabase
          .from('espacio')
          .update({
            'radio_latitud': posicion.latitude,

            'radio_longitud': posicion.longitude,

            'radio_metros': radio,
          })
          .eq('id_espacio', espacio['id_espacio']);

      await cargarConfiguracion();

      if (!mounted) {
        return;
      }

      mostrarMensaje('Ubicación GPS registrada correctamente.');
    } catch (error) {
      debugPrint('ERROR GPS: $error');

      mostrarMensaje('No fue posible registrar la ubicación GPS.', error: true);
    } finally {
      if (mounted) {
        setState(() {
          guardandoGps = false;
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
              'Activa la ubicación del teléfono para registrar correctamente la posición del espacio.',
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
            title: const Text('Permiso de ubicación'),

            content: const Text(
              'El permiso de ubicación fue bloqueado. Debes habilitarlo desde los ajustes de RegiServ.',
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
      if (!mounted) {
        return null;
      }

      final abrir = await showDialog<bool>(
        context: context,

        builder: (context) {
          return AlertDialog(
            title: const Text('Se requiere ubicación precisa'),

            content: const Text(
              'RegiServ necesita ubicación precisa para registrar correctamente la posición del espacio.',
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

    const configuracion = LocationSettings(
      accuracy: LocationAccuracy.best,

      distanceFilter: 0,

      timeLimit: Duration(seconds: 25),
    );

    return Geolocator.getCurrentPosition(locationSettings: configuracion);
  }

  // =============================================================
  // CONFIRMAR UBICACIÓN
  // =============================================================

  Future<int?> confirmarUbicacionGps(Position posicion) async {
    final radioController = TextEditingController(
      text: (espacio['radio_metros'] ?? 30).toString(),
    );

    final resultado = await showDialog<int>(
      context: context,
      barrierDismissible: false,

      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar ubicación'),

          content: SizedBox(
            width: 430,

            child: Column(
              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                const Text('RegiServ obtuvo la ubicación actual del teléfono.'),

                const SizedBox(height: 16),

                _DatoGps(
                  titulo: 'Latitud',

                  valor: posicion.latitude.toStringAsFixed(7),
                ),

                _DatoGps(
                  titulo: 'Longitud',

                  valor: posicion.longitude.toStringAsFixed(7),
                ),

                _DatoGps(
                  titulo: 'Precisión estimada',

                  valor: '${posicion.accuracy.toStringAsFixed(1)} m',
                ),

                const SizedBox(height: 18),

                TextField(
                  controller: radioController,

                  keyboardType: TextInputType.number,

                  decoration: const InputDecoration(
                    labelText: 'Radio permitido',

                    suffixText: 'metros',

                    helperText: '30 metros por defecto',

                    border: OutlineInputBorder(),

                    prefixIcon: Icon(Icons.radar_outlined),
                  ),
                ),
              ],
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },

              child: const Text('Cancelar'),
            ),

            ElevatedButton.icon(
              onPressed: () {
                final radio = int.tryParse(radioController.text.trim());

                if (radio == null || radio < 1 || radio > 500) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'El radio debe estar entre 1 y 500 metros.',
                      ),
                    ),
                  );

                  return;
                }

                Navigator.pop(context, radio);
              },

              icon: const Icon(Icons.location_on_outlined),

              label: const Text('Guardar ubicación'),
            ),
          ],
        );
      },
    );

    radioController.dispose();

    return resultado;
  }

  // =============================================================
  // NFC REAL - LEER UID DEL NTAG215
  // =============================================================

  Future<void> asociarNfc() async {
    if (!esDispositivoMovil) {
      mostrarMensaje(
        'La asociación NFC debe realizarse desde Android o iOS.',
        error: true,
      );

      return;
    }

    // ---------------------------------------------------------
    // CONFIRMAR REEMPLAZO
    // ---------------------------------------------------------

    if (nfcConfigurado) {
      final reemplazar = await showDialog<bool>(
        context: context,

        builder: (context) {
          return AlertDialog(
            title: const Text('Reemplazar NFC'),

            content: Text(
              'Este espacio ya tiene asociada la etiqueta ${espacio['nfcUid']}.\n\n'
              'La asociación actual quedará finalizada y la nueva etiqueta será registrada.',
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

                child: const Text('Continuar'),
              ),
            ],
          );
        },
      );

      if (reemplazar != true) {
        return;
      }
    }

    setState(() {
      guardandoNfc = true;

      mensajeProcesoNfc = 'Acerca el NTAG215 al teléfono...';
    });

    bool sesionActiva = false;

    try {
      // ---------------------------------------------------------
      // COMPROBAR NFC DEL TELÉFONO
      // ---------------------------------------------------------

      final disponibilidad = await NfcManager.instance.checkAvailability();

      if (disponibilidad == NfcAvailability.unsupported) {
        throw Exception('Este teléfono no posee NFC.');
      }

      if (disponibilidad == NfcAvailability.disabled) {
        throw Exception('El NFC del teléfono está desactivado.');
      }

      final completer = Completer<String>();

      // ---------------------------------------------------------
      // INICIAR LECTURA
      // NTAG215 = NFC-A / ISO 14443
      // ---------------------------------------------------------

      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},

        invalidateAfterFirstReadIos: true,

        alertMessageIos: 'Acerca el iPhone a la etiqueta NTAG215.',

        onSessionErrorIos: (error) {
          sesionActiva = false;

          if (!completer.isCompleted) {
            completer.completeError(Exception('La lectura NFC fue cancelada.'));
          }
        },

        onDiscovered: (NfcTag tag) async {
          try {
            final uid = obtenerUidTag(tag);

            if (uid.isEmpty) {
              throw Exception('No fue posible obtener el UID de la etiqueta.');
            }

            if (!completer.isCompleted) {
              completer.complete(uid);
            }

            try {
              await NfcManager.instance.stopSession(
                alertMessageIos: 'Etiqueta identificada correctamente.',
              );
            } catch (_) {}

            sesionActiva = false;
          } catch (error) {
            try {
              await NfcManager.instance.stopSession(
                errorMessageIos: 'No fue posible identificar la etiqueta.',
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

      // ---------------------------------------------------------
      // ESPERAR UID
      // ---------------------------------------------------------

      final uid = await completer.future.timeout(const Duration(seconds: 45));

      if (!mounted) {
        return;
      }

      setState(() {
        mensajeProcesoNfc = 'UID $uid detectado. Guardando asociación...';
      });

      // ---------------------------------------------------------
      // GUARDAR UID EN SUPABASE
      // ---------------------------------------------------------

      final respuesta = await supabase.rpc(
        'configurar_nfc_espacio',

        params: {'p_id_espacio': espacio['id_espacio'], 'p_uid_nfc': uid},
      );

      debugPrint(
        'RESPUESTA CONFIGURAR NFC: '
        '$respuesta',
      );

      await cargarConfiguracion();

      if (!mounted) {
        return;
      }

      mostrarMensaje('NFC asociada correctamente. UID: $uid');
    } on TimeoutException {
      mostrarMensaje(
        'No se detectó una etiqueta NFC dentro del tiempo disponible.',
        error: true,
      );
    } on PostgrestException catch (error) {
      debugPrint(
        'ERROR SUPABASE NFC: '
        '${error.message}',
      );

      mostrarMensaje(error.message, error: true);
    } catch (error) {
      debugPrint('ERROR NFC: $error');

      final mensaje = error.toString().replaceFirst('Exception: ', '');

      mostrarMensaje(mensaje, error: true);
    } finally {
      if (sesionActiva) {
        try {
          await NfcManager.instance.stopSession();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          guardandoNfc = false;

          mensajeProcesoNfc = null;
        });
      }
    }
  }

  // =============================================================
  // OBTENER UID DEL TAG
  // =============================================================

  String obtenerUidTag(NfcTag tag) {
    List<int>? bytesUid;

    // ---------------------------------------------------------
    // ANDROID
    // ---------------------------------------------------------

    if (defaultTargetPlatform == TargetPlatform.android) {
      final tagAndroid = NfcTagAndroid.from(tag);

      if (tagAndroid == null) {
        throw Exception(
          'Android no pudo obtener la información de la etiqueta NFC.',
        );
      }

      bytesUid = tagAndroid.id;
    }

    // ---------------------------------------------------------
    // IOS
    // ---------------------------------------------------------

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final tagIos = MiFareIos.from(tag);

      if (tagIos == null) {
        throw Exception(
          'La etiqueta detectada no corresponde a una etiqueta MIFARE/NTAG compatible.',
        );
      }

      bytesUid = tagIos.identifier;
    }

    if (bytesUid == null || bytesUid.isEmpty) {
      throw Exception('La etiqueta NFC no entregó un UID.');
    }

    // NTAG215 utiliza UID de 7 bytes.
    if (bytesUid.length != 7) {
      throw Exception(
        'El UID leído tiene ${bytesUid.length} bytes. '
        'Verifica que la etiqueta corresponda a un NTAG215.',
      );
    }

    return bytesUid
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,

        surfaceTintColor: Colors.white,

        elevation: 0,

        title: const Text(
          'Configurar espacio',

          style: TextStyle(
            fontWeight: FontWeight.bold,

            color: Color(0xFF1F2937),
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Actualizar',

            onPressed: cargando ? null : cargarConfiguracion,

            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : mensajeError != null
          ? _ErrorConfiguracion(
              mensaje: mensajeError!,

              onReintentar: cargarConfiguracion,
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),

                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 700),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        // ===============================
                        // DATOS DEL ESPACIO
                        // ===============================

                        _TarjetaEspacio(espacio: espacio),

                        const SizedBox(height: 20),

                        // ===============================
                        // ESTADO
                        // ===============================
                        _EstadoConfiguracion(completa: configuracionCompleta),

                        const SizedBox(height: 26),

                        const Text(
                          'Configuración física',

                          style: TextStyle(
                            fontSize: 20,

                            fontWeight: FontWeight.bold,

                            color: Color(0xFF1F2937),
                          ),
                        ),

                        const SizedBox(height: 6),

                        const Text(
                          'Realiza esta configuración desde el lugar físico donde está instalado el espacio.',

                          style: TextStyle(
                            color: Color(0xFF6B7280),

                            height: 1.4,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ===============================
                        // GPS
                        // ===============================
                        _TarjetaConfiguracion(
                          titulo: 'Ubicación GPS',

                          descripcion: gpsConfigurado
                              ? '${espacio['radio_latitud']}, '
                                    '${espacio['radio_longitud']} · '
                                    'Radio ${espacio['radio_metros'] ?? 30} m'
                              : 'La ubicación física todavía no ha sido registrada.',

                          configurado: gpsConfigurado,

                          procesando: guardandoGps,

                          icono: Icons.location_on_outlined,

                          textoBoton: gpsConfigurado
                              ? 'Actualizar ubicación'
                              : 'Registrar ubicación actual',

                          textoProcesando: 'Obteniendo ubicación...',

                          onPressed: registrarGps,
                        ),

                        const SizedBox(height: 14),

                        // ===============================
                        // NFC
                        // ===============================
                        _TarjetaConfiguracion(
                          titulo: 'Etiqueta NFC',

                          descripcion: nfcConfigurado
                              ? 'UID: ${espacio['nfcUid']}'
                              : 'No existe una etiqueta NFC activa asociada.',

                          configurado: nfcConfigurado,

                          procesando: guardandoNfc,

                          icono: Icons.nfc_outlined,

                          textoBoton: nfcConfigurado
                              ? 'Reemplazar NFC'
                              : 'Asociar NFC',

                          textoProcesando:
                              mensajeProcesoNfc ?? 'Esperando NFC...',

                          onPressed: asociarNfc,
                        ),

                        const SizedBox(height: 22),

                        // ===============================
                        // INFORMACIÓN NFC
                        // ===============================
                        Container(
                          width: double.infinity,

                          padding: const EdgeInsets.all(15),

                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),

                            borderRadius: BorderRadius.circular(14),
                          ),

                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [
                              Icon(
                                Icons.info_outline,

                                color: Color(0xFF1565C0),
                              ),

                              SizedBox(width: 10),

                              Expanded(
                                child: Text(
                                  'RegiServ utiliza el UID físico del NTAG215 para identificar cada espacio. '
                                  'La aplicación solo lee el identificador de fábrica de la etiqueta; no modifica ni escribe su contenido.',

                                  style: TextStyle(
                                    fontSize: 13,

                                    height: 1.45,

                                    color: Color(0xFF1E40AF),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (!esDispositivoMovil) ...[
                          const SizedBox(height: 12),

                          Container(
                            width: double.infinity,

                            padding: const EdgeInsets.all(15),

                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),

                              borderRadius: BorderRadius.circular(14),
                            ),

                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [
                                Icon(
                                  Icons.phone_android_outlined,

                                  color: Color(0xFFEA580C),
                                ),

                                SizedBox(width: 10),

                                Expanded(
                                  child: Text(
                                    'La configuración física de GPS y NFC está disponible en Android e iOS. '
                                    'Desde navegador puedes consultar la configuración existente, pero debes usar un teléfono para registrar o reemplazar una etiqueta NFC.',

                                    style: TextStyle(
                                      fontSize: 13,

                                      height: 1.45,

                                      color: Color(0xFF9A3412),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
// TARJETA ESPACIO
// =================================================================

class _TarjetaEspacio extends StatelessWidget {
  final Map<String, dynamic> espacio;

  const _TarjetaEspacio({required this.espacio});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Container(
            width: 56,

            height: 56,

            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),

              borderRadius: BorderRadius.circular(14),
            ),

            child: const Icon(
              Icons.meeting_room_outlined,

              size: 30,

              color: Color(0xFF7C3AED),
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  (espacio['nombreVisible'] ?? espacio['nombre'] ?? 'Espacio')
                      .toString(),

                  style: const TextStyle(
                    fontSize: 21,

                    fontWeight: FontWeight.bold,

                    color: Color(0xFF1F2937),
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  '${espacio['edificioNombre'] ?? 'Edificio'} · '
                  'Piso ${espacio['pisoNumero'] ?? '-'}',

                  style: const TextStyle(color: Color(0xFF6B7280)),
                ),

                const SizedBox(height: 3),

                Text(
                  'Código ${espacio['codigo'] ?? '-'} · '
                  '${espacio['tipo'] ?? 'Espacio'}',

                  style: const TextStyle(
                    fontSize: 13,

                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// ESTADO GENERAL
// =================================================================

class _EstadoConfiguracion extends StatelessWidget {
  final bool completa;

  const _EstadoConfiguracion({required this.completa});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: completa ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),

        borderRadius: BorderRadius.circular(14),
      ),

      child: Row(
        children: [
          Icon(
            completa
                ? Icons.check_circle_outline
                : Icons.pending_actions_outlined,

            color: completa ? const Color(0xFF16A34A) : const Color(0xFFD97706),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  completa
                      ? 'Configuración completa'
                      : 'Configuración pendiente',

                  style: TextStyle(
                    fontWeight: FontWeight.bold,

                    color: completa
                        ? const Color(0xFF166534)
                        : const Color(0xFF92400E),
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  completa
                      ? 'El espacio tiene ubicación GPS y NFC configuradas.'
                      : 'Registra la ubicación GPS y asocia una etiqueta NFC.',

                  style: TextStyle(
                    fontSize: 13,

                    height: 1.4,

                    color: completa
                        ? const Color(0xFF166534)
                        : const Color(0xFF92400E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// DATO GPS
// =================================================================

class _DatoGps extends StatelessWidget {
  final String titulo;
  final String valor;

  const _DatoGps({required this.titulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),

      child: Row(
        children: [
          Expanded(
            child: Text(
              titulo,

              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          ),

          Text(
            valor,

            style: const TextStyle(
              fontWeight: FontWeight.w600,

              color: Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// TARJETA DE CONFIGURACIÓN
// =================================================================

class _TarjetaConfiguracion extends StatelessWidget {
  final String titulo;
  final String descripcion;

  final bool configurado;
  final bool procesando;

  final IconData icono;

  final String textoBoton;
  final String textoProcesando;

  final VoidCallback onPressed;

  const _TarjetaConfiguracion({
    required this.titulo,
    required this.descripcion,
    required this.configurado,
    required this.procesando,
    required this.icono,
    required this.textoBoton,
    required this.textoProcesando,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Container(
                width: 48,

                height: 48,

                decoration: BoxDecoration(
                  color: configurado
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFFFF7ED),

                  borderRadius: BorderRadius.circular(12),
                ),

                child: Icon(
                  icono,

                  color: configurado
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFEA580C),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      titulo,

                      style: const TextStyle(
                        fontSize: 17,

                        fontWeight: FontWeight.bold,

                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      descripcion,

                      style: const TextStyle(
                        fontSize: 13,

                        height: 1.35,

                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,

                  vertical: 5,
                ),

                decoration: BoxDecoration(
                  color: configurado
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFFFF7ED),

                  borderRadius: BorderRadius.circular(20),
                ),

                child: Text(
                  configurado ? 'Configurado' : 'Pendiente',

                  style: TextStyle(
                    fontSize: 11,

                    fontWeight: FontWeight.w600,

                    color: configurado
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFEA580C),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

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

              label: Text(procesando ? textoProcesando : textoBoton),
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// ERROR
// =================================================================

class _ErrorConfiguracion extends StatelessWidget {
  final String mensaje;

  final Future<void> Function() onReintentar;

  const _ErrorConfiguracion({
    required this.mensaje,
    required this.onReintentar,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            const Icon(
              Icons.cloud_off_outlined,

              size: 58,

              color: Color(0xFF9CA3AF),
            ),

            const SizedBox(height: 14),

            Text(mensaje, textAlign: TextAlign.center),

            const SizedBox(height: 18),

            ElevatedButton.icon(
              onPressed: () {
                onReintentar();
              },

              icon: const Icon(Icons.refresh),

              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
