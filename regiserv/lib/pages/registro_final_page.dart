import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auxiliar_home_page.dart';

import 'dart:convert';

import '../core/storage/hive_local_storage.dart';
import '../core/sync/registro_final_fallback_service.dart';

// =================================================================
// MODELO LOCAL DE UNA FOTOGRAFÍA
// =================================================================

class _EvidenciaLocal {
  final XFile archivo;
  final Uint8List bytes;

  // Se utilizan para evitar volver a subir una fotografía
  // si ya fue almacenada correctamente en Supabase.
  String? rutaRemota;
  bool registrada = false;

  _EvidenciaLocal({required this.archivo, required this.bytes});
}

// =================================================================
// REGISTRO FINAL
// =================================================================

class RegistroFinalPage extends StatefulWidget {
  final int idRegistroAseo;

  final String nombreAuxiliar;
  final String lugar;

  final DateTime horaInicio;
  final DateTime horaTermino;

  const RegistroFinalPage({
    super.key,
    required this.idRegistroAseo,
    required this.nombreAuxiliar,
    required this.lugar,
    required this.horaInicio,
    required this.horaTermino,
  });

  @override
  State<RegistroFinalPage> createState() => _RegistroFinalPageState();
}

class _RegistroFinalPageState extends State<RegistroFinalPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  // =============================================================
  // ESTADO DEL REGISTRO
  // =============================================================

  String? estadoSeleccionado;
  String? categoriaSeleccionada;

  final TextEditingController motivoParcialController = TextEditingController();

  final TextEditingController detalleObservacionController =
      TextEditingController();

  // =============================================================
  // FOTOGRAFÍAS
  // =============================================================

  final ImagePicker imagePicker = ImagePicker();

  final List<_EvidenciaLocal> fotografias = <_EvidenciaLocal>[];

  bool tomandoFotografia = false;

  String? errorFotografia;

  // =============================================================
  // SUPABASE
  // =============================================================

  bool cargandoCategorias = true;
  bool enviandoRegistro = false;

  String? mensajeProceso;
  String? errorCategorias;

  final List<String> categorias = <String>[];

  // =============================================================
  // INIT
  // =============================================================

  @override
  void initState() {
    super.initState();

    cargarCategorias();
  }

  @override
  void dispose() {
    motivoParcialController.dispose();
    detalleObservacionController.dispose();

    super.dispose();
  }

  // =============================================================
  // CARGAR TIPOS DE OBSERVACIÓN
  // =============================================================

  Future<void> cargarCategorias() async {
    if (!mounted) {
      return;
    }

    setState(() {
      cargandoCategorias = true;
      errorCategorias = null;
    });

    try {
      final dynamic respuesta = await supabase
          .from('tipo_observacion')
          .select('nombre')
          .eq('activo', true)
          .order('nombre');

      final List<dynamic> filas = respuesta is List ? respuesta : <dynamic>[];

      final List<String> nombres = <String>[];

      for (final dynamic fila in filas) {
        if (fila is! Map) {
          continue;
        }

        final dynamic valor = fila['nombre'];

        if (valor is String && valor.trim().isNotEmpty) {
          nombres.add(valor.trim());
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        categorias
          ..clear()
          ..addAll(nombres);

        cargandoCategorias = false;
      });
    } catch (e, stackTrace) {
      debugPrint('ERROR cargarCategorias: $e');

      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        cargandoCategorias = false;

        errorCategorias = 'No fue posible cargar las categorías.';
      });
    }
  }

  // =============================================================
  // FORMATOS
  // =============================================================

  String formatearHora(DateTime fecha) {
    final String hora = fecha.hour.toString().padLeft(2, '0');

    final String minuto = fecha.minute.toString().padLeft(2, '0');

    return '$hora:$minuto';
  }

  String obtenerDuracion() {
    final Duration duracion = widget.horaTermino.difference(widget.horaInicio);

    if (duracion.isNegative) {
      return '0 min';
    }

    final int minutos = duracion.inMinutes;

    if (minutos < 1) {
      return '< 1 min';
    }

    return '$minutos min';
  }

  // =============================================================
  // TOMAR FOTOGRAFÍA
  // =============================================================

  Future<void> tomarFotografia() async {
    if (tomandoFotografia || enviandoRegistro) {
      return;
    }

    setState(() {
      tomandoFotografia = true;
      errorFotografia = null;
    });

    try {
      final XFile? imagen = await imagePicker.pickImage(
        source: ImageSource.camera,

        preferredCameraDevice: CameraDevice.rear,

        imageQuality: 80,

        maxWidth: 1920,
      );

      // El usuario cerró la cámara
      // sin capturar una fotografía.
      if (imagen == null) {
        return;
      }

      final Uint8List bytes = await imagen.readAsBytes();

      if (bytes.isEmpty) {
        throw Exception('La fotografía capturada está vacía.');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        fotografias.add(_EvidenciaLocal(archivo: imagen, bytes: bytes));

        errorFotografia = null;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              fotografias.length == 1
                  ? 'Fotografía agregada correctamente.'
                  : 'Fotografía ${fotografias.length} agregada correctamente.',
            ),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
    } catch (e, stackTrace) {
      debugPrint('ERROR tomarFotografia: $e');

      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        errorFotografia =
            'No fue posible abrir la cámara o capturar la fotografía.';
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(errorFotografia!),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          tomandoFotografia = false;
        });
      }
    }
  }

  // =============================================================
  // ELIMINAR FOTOGRAFÍA
  // =============================================================

  Future<void> eliminarFotografia(int indice) async {
    if (enviandoRegistro || tomandoFotografia) {
      return;
    }

    if (indice < 0 || indice >= fotografias.length) {
      return;
    }

    final _EvidenciaLocal foto = fotografias[indice];

    // Una evidencia ya persistida no debería
    // eliminarse solamente desde la memoria local.
    if (foto.registrada) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Esta fotografía ya fue almacenada y no puede eliminarse desde esta pantalla.',
            ),
          ),
        );

      return;
    }

    setState(() {
      fotografias.removeAt(indice);
    });
  }

  // =============================================================
  // TIPO DE ARCHIVO
  // =============================================================

  String obtenerExtension(_EvidenciaLocal foto) {
    final String mime = (foto.archivo.mimeType ?? '').toLowerCase();

    if (mime == 'image/png') {
      return 'png';
    }

    if (mime == 'image/webp') {
      return 'webp';
    }

    return 'jpg';
  }

  String obtenerMimeType(_EvidenciaLocal foto) {
    final String mime = (foto.archivo.mimeType ?? '').toLowerCase();

    if (mime == 'image/png') {
      return 'image/png';
    }

    if (mime == 'image/webp') {
      return 'image/webp';
    }

    return 'image/jpeg';
  }

  // =============================================================
  // SUBIR TODAS LAS EVIDENCIAS
  // =============================================================

  Future<void> subirEvidencias() async {
    final User? usuario = supabase.auth.currentUser;

    if (usuario == null) {
      throw Exception('No existe una sesión autenticada.');
    }

    if (fotografias.isEmpty) {
      throw Exception('Debes tomar al menos una fotografía.');
    }

    for (int i = 0; i < fotografias.length; i++) {
      final _EvidenciaLocal foto = fotografias[i];

      // ---------------------------------------------------------
      // YA FUE REGISTRADA
      // ---------------------------------------------------------

      if (foto.registrada) {
        continue;
      }

      if (mounted) {
        setState(() {
          mensajeProceso =
              'Subiendo fotografía ${i + 1} de ${fotografias.length}...';
        });
      }

      final String extension = obtenerExtension(foto);

      final String mimeType = obtenerMimeType(foto);

      final int timestamp = DateTime.now().microsecondsSinceEpoch;

      final String nombreArchivo = 'evidencia_${timestamp}_${i + 1}.$extension';

      final String rutaArchivo =
          '${usuario.id}/'
          '${widget.idRegistroAseo}/'
          '$nombreArchivo';

      String? rutaSubida;

      try {
        // -------------------------------------------------------
        // 1. SUBIR ARCHIVO AL STORAGE
        // -------------------------------------------------------

        await supabase.storage
            .from('evidencias-aseo')
            .uploadBinary(
              rutaArchivo,
              foto.bytes,
              fileOptions: FileOptions(contentType: mimeType, upsert: false),
            );

        rutaSubida = rutaArchivo;

        // -------------------------------------------------------
        // 2. REGISTRAR EN TABLA EVIDENCIA
        // -------------------------------------------------------

        final dynamic respuesta = await supabase.rpc(
          'registrar_evidencia_aseo',
          params: {
            'p_id_registro_aseo': widget.idRegistroAseo,

            'p_ruta_archivo': rutaArchivo,

            'p_nombre_archivo': nombreArchivo,
          },
        );

        if (respuesta is! Map) {
          throw Exception('Respuesta inválida al registrar la evidencia.');
        }

        final Map<String, dynamic> resultado = Map<String, dynamic>.from(
          respuesta,
        );

        if (resultado['ok'] != true) {
          throw Exception('No fue posible registrar la evidencia.');
        }

        // -------------------------------------------------------
        // MARCAR ESTA FOTO COMO YA PERSISTIDA
        // -------------------------------------------------------

        foto.rutaRemota = rutaArchivo;

        foto.registrada = true;
      } catch (e) {
        // Si el archivo alcanzó a subirse al Storage,
        // pero falló el registro en la BD, lo eliminamos
        // para evitar archivos huérfanos.
        if (rutaSubida != null && !foto.registrada) {
          try {
            await supabase.storage.from('evidencias-aseo').remove(<String>[
              rutaSubida,
            ]);
          } catch (errorEliminar) {
            debugPrint(
              'No fue posible limpiar evidencia huérfana: '
              '$errorEliminar',
            );
          }
        }

        rethrow;
      }
    }
  }

  // =============================================================
  // VALIDACIÓN DEL FORMULARIO
  // =============================================================

  bool get formularioValido {
    if (estadoSeleccionado == null) {
      return false;
    }

    // Mínimo una evidencia.
    if (fotografias.isEmpty) {
      return false;
    }

    if (estadoSeleccionado == 'Parcial') {
      if (motivoParcialController.text.trim().isEmpty) {
        return false;
      }
    }

    if (estadoSeleccionado == 'Con Observaciones') {
      if (categoriaSeleccionada == null) {
        return false;
      }

      if (detalleObservacionController.text.trim().isEmpty) {
        return false;
      }
    }

    return true;
  }

  // =============================================================
  // ENVIAR REGISTRO
  // =============================================================

  Future<bool> guardarComoPendientePorConexion({
    required String? comentario,
    required String? tipoObservacion,
    required String? detalleObservacion,
  }) async {
    final usuario = supabase.auth.currentUser;

    if (usuario == null) {
      return false;
    }

    final RegistroFinalFallbackService fallback = RegistroFinalFallbackService(
      localStorage: HiveLocalStorage.instance,
      supabase: supabase,
    );

    final bool disponible = await fallback.backendDisponible();

    // Si Supabase sí responde, el error original NO se considera
    // un problema de conexión y debe mostrarse normalmente.
    if (disponible) {
      return false;
    }

    final List<Map<String, dynamic>> evidenciasPendientes =
        <Map<String, dynamic>>[];

    for (final _EvidenciaLocal foto in fotografias) {
      // Si esta fotografía ya alcanzó a subirse y su RPC
      // registrar_evidencia_aseo terminó correctamente,
      // NO la guardamos de nuevo para evitar duplicados.
      if (foto.registrada) {
        continue;
      }

      final String nombreOriginal = foto.archivo.name.trim();

      final String nombreArchivo = nombreOriginal.isNotEmpty
          ? nombreOriginal
          : 'foto_${DateTime.now().microsecondsSinceEpoch}.jpg';

      final String mimeType =
          foto.archivo.mimeType ?? _mimeDesdeNombreFallback(nombreArchivo);

      evidenciasPendientes.add(<String, dynamic>{
        'nombre_archivo': nombreArchivo,
        'mime_type': mimeType,
        'fecha_fotografia': DateTime.now().toUtc().toIso8601String(),
        'bytes_base64': base64Encode(foto.bytes),
      });
    }

    await fallback.guardarPendiente(
      idUsuario: usuario.id,
      idRegistroAseo: widget.idRegistroAseo,
      estadoAseo: estadoSeleccionado!,
      horaInicio: widget.horaInicio,
      horaTermino: widget.horaTermino,
      lugar: widget.lugar,
      nombreAuxiliar: widget.nombreAuxiliar,
      comentario: comentario,
      tipoObservacion: tipoObservacion,
      detalleObservacion: detalleObservacion,
      evidenciasPendientes: evidenciasPendientes,
    );

    if (!mounted) {
      return true;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          icon: const Icon(
            Icons.cloud_upload_outlined,
            color: Color(0xFFD97706),
            size: 48,
          ),
          title: const Text(
            'Pendiente de sincronización',
            textAlign: TextAlign.center,
          ),
          content: const Text(
            'Se perdió la conexión antes de completar el envío. '
            'El registro y las fotografías pendientes quedaron guardados '
            'en este dispositivo y se sincronizarán cuando vuelva Internet.',
            textAlign: TextAlign.center,
          ),
          actions: [
            Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Aceptar'),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return true;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const AuxiliarHomePage()),
      (route) => false,
    );

    return true;
  }

  String _mimeDesdeNombreFallback(String nombre) {
    final String lower = nombre.toLowerCase();

    if (lower.endsWith('.png')) {
      return 'image/png';
    }

    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }

    return 'image/jpeg';
  }

  Future<void> enviarRegistro() async {
    if (!formularioValido || enviandoRegistro || tomandoFotografia) {
      return;
    }

    final int cantidad = fotografias.length;

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('¿Enviar registro?'),
          content: Text(
            cantidad == 1
                ? 'Se enviará el registro junto con 1 fotografía de evidencia.'
                : 'Se enviará el registro junto con $cantidad fotografías de evidencia.',
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
              child: const Text('Enviar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      enviandoRegistro = true;

      mensajeProceso = 'Preparando evidencias...';
    });

    try {
      // =========================================================
      // 1. SUBIR TODAS LAS FOTOGRAFÍAS
      // =========================================================

      await subirEvidencias();

      if (!mounted) {
        return;
      }

      setState(() {
        mensajeProceso = 'Completando registro...';
      });

      // =========================================================
      // 2. PREPARAR ESTADO FINAL
      // =========================================================

      String? comentario;
      String? tipoObservacion;
      String? detalleObservacion;

      if (estadoSeleccionado == 'Parcial') {
        comentario = motivoParcialController.text.trim();
      }

      if (estadoSeleccionado == 'Con Observaciones') {
        tipoObservacion = categoriaSeleccionada;

        detalleObservacion = detalleObservacionController.text.trim();
      }

      // =========================================================
      // 3. COMPLETAR REGISTRO
      // =========================================================

      final dynamic respuesta = await supabase.rpc(
        'completar_registro_aseo',
        params: {
          'p_id_registro_aseo': widget.idRegistroAseo,

          'p_estado': estadoSeleccionado,

          'p_comentario': comentario,

          'p_tipo_observacion': tipoObservacion,

          'p_detalle_observacion': detalleObservacion,
        },
      );

      if (respuesta is! Map) {
        throw Exception('Respuesta inválida al completar el registro.');
      }

      final Map<String, dynamic> resultado = Map<String, dynamic>.from(
        respuesta,
      );

      if (resultado['ok'] != true) {
        throw Exception('No fue posible completar el registro.');
      }

      // El registro y las evidencias ya quedaron aceptados en Supabase.
      // Eliminar la marca local evita bloquear labores futuras o volver a
      // presentar este registro al reiniciar la aplicación.
      final usuarioConfirmado = supabase.auth.currentUser;
      if (usuarioConfirmado != null) {
        try {
          await HiveLocalStorage.instance.eliminarLaborEnCurso(
            usuarioConfirmado.id,
          );
        } catch (error) {
          // La operación remota YA fue confirmada. Un problema local
          // no debe generar otro envío ni duplicar el registro.
          debugPrint('AVISO LIMPIEZA LOCAL POSREGISTRO: $error');
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        mensajeProceso = null;
      });

      // =========================================================
      // CONFIRMACIÓN
      // =========================================================

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            icon: const Icon(
              Icons.check_circle,
              color: Color(0xFF16A34A),
              size: 48,
            ),
            title: const Text('Registro enviado', textAlign: TextAlign.center),
            content: Text(
              fotografias.length == 1
                  ? 'La labor fue registrada correctamente como '
                        '"${resultado['estado'] ?? estadoSeleccionado}" '
                        'con 1 fotografía de evidencia.'
                  : 'La labor fue registrada correctamente como '
                        '"${resultado['estado'] ?? estadoSeleccionado}" '
                        'con ${fotografias.length} fotografías de evidencia.',
              textAlign: TextAlign.center,
            ),
            actions: [
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Aceptar'),
                ),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }

      // =========================================================
      // VOLVER AL HOME
      // =========================================================

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AuxiliarHomePage()),
        (route) => false,
      );
    } catch (e, stackTrace) {
      debugPrint('ERROR enviarRegistro: $e');

      debugPrint('$stackTrace');

      String? comentario;
      String? tipoObservacion;
      String? detalleObservacion;

      if (estadoSeleccionado == 'Parcial') {
        comentario = motivoParcialController.text.trim();
      }

      if (estadoSeleccionado == 'Con Observaciones') {
        tipoObservacion = categoriaSeleccionada;

        detalleObservacion = detalleObservacionController.text.trim();
      }

      try {
        final bool guardadoLocal = await guardarComoPendientePorConexion(
          comentario: comentario,
          tipoObservacion: tipoObservacion,
          detalleObservacion: detalleObservacion,
        );

        if (guardadoLocal) {
          return;
        }
      } catch (errorLocal, stackLocal) {
        debugPrint('ERROR GUARDANDO FALLBACK LOCAL: $errorLocal');

        debugPrint('$stackLocal');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        enviandoRegistro = false;
        mensajeProceso = null;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('No fue posible enviar el registro: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
    }
  }

  // =============================================================
  // BUILD
  // =============================================================

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
            'Completar registro',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
        ),

        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),

            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    // =================================================
                    // RESUMEN
                    // =================================================

                    Container(
                      width: double.infinity,

                      padding: const EdgeInsets.all(20),

                      decoration: BoxDecoration(
                        color: Colors.white,

                        borderRadius: BorderRadius.circular(16),
                      ),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          const Text(
                            'Resumen de la labor',

                            style: TextStyle(
                              fontSize: 19,

                              fontWeight: FontWeight.bold,

                              color: Color(0xFF1F2937),
                            ),
                          ),

                          const SizedBox(height: 18),

                          _DatoTexto(
                            titulo: 'Registro',

                            valor: '#${widget.idRegistroAseo}',
                          ),

                          const SizedBox(height: 14),

                          _DatoTexto(
                            titulo: 'Auxiliar',

                            valor: widget.nombreAuxiliar,
                          ),

                          const SizedBox(height: 14),

                          _DatoTexto(titulo: 'Lugar', valor: widget.lugar),

                          const SizedBox(height: 18),

                          const Divider(),

                          const SizedBox(height: 16),

                          Row(
                            children: [
                              Expanded(
                                child: _DatoResumen(
                                  titulo: 'Inicio',

                                  valor: formatearHora(widget.horaInicio),

                                  icono: Icons.schedule,
                                ),
                              ),

                              const SizedBox(width: 10),

                              Expanded(
                                child: _DatoResumen(
                                  titulo: 'Término',

                                  valor: formatearHora(widget.horaTermino),

                                  icono: Icons.schedule_outlined,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          _DatoResumen(
                            titulo: 'Duración',

                            valor: obtenerDuracion(),

                            icono: Icons.timer_outlined,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 26),

                    // =================================================
                    // ESTADO
                    // =================================================
                    const Text(
                      '¿Cómo quedó el aseo?',

                      style: TextStyle(
                        fontSize: 23,

                        fontWeight: FontWeight.bold,

                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Selecciona una opción.',

                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),

                    const SizedBox(height: 18),

                    // =================================================
                    // COMPLETO
                    // =================================================
                    _OpcionEstado(
                      titulo: 'Completo',

                      descripcion: 'La labor se realizó completamente.',

                      icono: Icons.check_circle_outline,

                      seleccionado: estadoSeleccionado == 'Completo',

                      onTap: () {
                        setState(() {
                          estadoSeleccionado = 'Completo';

                          categoriaSeleccionada = null;

                          motivoParcialController.clear();

                          detalleObservacionController.clear();
                        });
                      },
                    ),

                    const SizedBox(height: 12),

                    // =================================================
                    // PARCIAL
                    // =================================================
                    _OpcionEstado(
                      titulo: 'Parcial',

                      descripcion: 'La labor no pudo completarse totalmente.',

                      icono: Icons.timelapse_outlined,

                      seleccionado: estadoSeleccionado == 'Parcial',

                      onTap: () {
                        setState(() {
                          estadoSeleccionado = 'Parcial';

                          categoriaSeleccionada = null;

                          detalleObservacionController.clear();
                        });
                      },
                    ),

                    if (estadoSeleccionado == 'Parcial') ...[
                      const SizedBox(height: 14),

                      TextField(
                        controller: motivoParcialController,

                        maxLines: 3,

                        onChanged: (_) {
                          setState(() {});
                        },

                        decoration: InputDecoration(
                          labelText: 'Motivo *',

                          hintText: 'Explica brevemente por qué quedó parcial.',

                          alignLabelWithHint: true,

                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // =================================================
                    // CON OBSERVACIONES
                    // =================================================
                    _OpcionEstado(
                      titulo: 'Con Observaciones',

                      descripcion:
                          'Existe una situación que requiere atención.',

                      icono: Icons.warning_amber_rounded,

                      seleccionado: estadoSeleccionado == 'Con Observaciones',

                      onTap: () {
                        setState(() {
                          estadoSeleccionado = 'Con Observaciones';

                          motivoParcialController.clear();
                        });
                      },
                    ),

                    if (estadoSeleccionado == 'Con Observaciones') ...[
                      const SizedBox(height: 14),

                      if (cargandoCategorias)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),

                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (errorCategorias != null)
                        Container(
                          width: double.infinity,

                          padding: const EdgeInsets.all(14),

                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),

                            borderRadius: BorderRadius.circular(12),
                          ),

                          child: Column(
                            children: [
                              Text(
                                errorCategorias!,

                                style: const TextStyle(
                                  color: Color(0xFFC2410C),
                                ),
                              ),

                              TextButton(
                                onPressed: cargarCategorias,

                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          value: categoriaSeleccionada,

                          isExpanded: true,

                          decoration: InputDecoration(
                            labelText: 'Categoría *',

                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),

                          items: categorias.map((categoria) {
                            return DropdownMenuItem<String>(
                              value: categoria,

                              child: Text(categoria),
                            );
                          }).toList(),

                          onChanged: (valor) {
                            setState(() {
                              categoriaSeleccionada = valor;
                            });
                          },
                        ),

                      const SizedBox(height: 14),

                      TextField(
                        controller: detalleObservacionController,

                        maxLines: 3,

                        onChanged: (_) {
                          setState(() {});
                        },

                        decoration: InputDecoration(
                          labelText: 'Detalle *',

                          hintText: 'Describe brevemente la situación.',

                          alignLabelWithHint: true,

                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 28),

                    // =================================================
                    // EVIDENCIAS FOTOGRÁFICAS
                    // =================================================
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Evidencias fotográficas',

                            style: TextStyle(
                              fontSize: 21,

                              fontWeight: FontWeight.bold,

                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ),

                        if (fotografias.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,

                              vertical: 5,
                            ),

                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),

                              borderRadius: BorderRadius.circular(20),
                            ),

                            child: Text(
                              '${fotografias.length} ${fotografias.length == 1 ? 'foto' : 'fotos'}',

                              style: const TextStyle(
                                color: Color(0xFF1565C0),

                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Debes registrar al menos una fotografía. '
                      'Puedes agregar todas las evidencias que necesites.',

                      style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
                    ),

                    const SizedBox(height: 16),

                    // =================================================
                    // SIN FOTOGRAFÍAS
                    // =================================================
                    if (fotografias.isEmpty)
                      Container(
                        width: double.infinity,

                        padding: const EdgeInsets.all(24),

                        decoration: BoxDecoration(
                          color: Colors.white,

                          borderRadius: BorderRadius.circular(16),

                          border: Border.all(
                            color: errorFotografia != null
                                ? const Color(0xFFFCA5A5)
                                : const Color(0xFFE5E7EB),
                          ),
                        ),

                        child: Column(
                          children: [
                            Icon(
                              errorFotografia != null
                                  ? Icons.error_outline
                                  : Icons.camera_alt_outlined,

                              size: 48,

                              color: errorFotografia != null
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF1565C0),
                            ),

                            const SizedBox(height: 10),

                            Text(
                              errorFotografia ??
                                  'Aún no has agregado ninguna fotografía.',

                              textAlign: TextAlign.center,

                              style: TextStyle(
                                color: errorFotografia != null
                                    ? const Color(0xFFB91C1C)
                                    : const Color(0xFF6B7280),
                              ),
                            ),

                            const SizedBox(height: 18),

                            SizedBox(
                              width: double.infinity,

                              child: ElevatedButton.icon(
                                onPressed: tomandoFotografia || enviandoRegistro
                                    ? null
                                    : tomarFotografia,

                                icon: tomandoFotografia
                                    ? const SizedBox(
                                        width: 18,

                                        height: 18,

                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,

                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.camera_alt),

                                label: Text(
                                  tomandoFotografia
                                      ? 'Abriendo cámara...'
                                      : 'Tomar fotografía',
                                ),

                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1565C0),

                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // =================================================
                    // LISTA DE FOTOGRAFÍAS
                    // =================================================
                    if (fotografias.isNotEmpty)
                      Container(
                        width: double.infinity,

                        padding: const EdgeInsets.all(16),

                        decoration: BoxDecoration(
                          color: Colors.white,

                          borderRadius: BorderRadius.circular(16),

                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            GridView.builder(
                              shrinkWrap: true,

                              physics: const NeverScrollableScrollPhysics(),

                              itemCount: fotografias.length,

                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,

                                    crossAxisSpacing: 10,

                                    mainAxisSpacing: 10,

                                    childAspectRatio: 1,
                                  ),

                              itemBuilder: (context, index) {
                                final _EvidenciaLocal foto = fotografias[index];

                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(12),

                                  child: Stack(
                                    fit: StackFit.expand,

                                    children: [
                                      Image.memory(
                                        foto.bytes,

                                        fit: BoxFit.cover,

                                        gaplessPlayback: true,
                                      ),

                                      // FOTO N°
                                      Positioned(
                                        left: 7,

                                        bottom: 7,

                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,

                                            vertical: 4,
                                          ),

                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(
                                              0.65,
                                            ),

                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),

                                          child: Text(
                                            'Foto ${index + 1}',

                                            style: const TextStyle(
                                              color: Colors.white,

                                              fontSize: 12,

                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),

                                      // ELIMINAR
                                      Positioned(
                                        top: 6,

                                        right: 6,

                                        child: Material(
                                          color: Colors.white,

                                          shape: const CircleBorder(),

                                          child: IconButton(
                                            tooltip: 'Eliminar fotografía',

                                            onPressed:
                                                foto.registrada ||
                                                    enviandoRegistro
                                                ? null
                                                : () {
                                                    eliminarFotografia(index);
                                                  },

                                            icon: const Icon(
                                              Icons.delete_outline,

                                              color: Color(0xFFDC2626),
                                            ),

                                            iconSize: 21,

                                            constraints: const BoxConstraints(
                                              minWidth: 38,

                                              minHeight: 38,
                                            ),
                                          ),
                                        ),
                                      ),

                                      if (foto.registrada)
                                        Positioned(
                                          left: 7,

                                          top: 7,

                                          child: Container(
                                            padding: const EdgeInsets.all(5),

                                            decoration: const BoxDecoration(
                                              color: Color(0xFF16A34A),

                                              shape: BoxShape.circle,
                                            ),

                                            child: const Icon(
                                              Icons.cloud_done,

                                              size: 16,

                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),

                            const SizedBox(height: 16),

                            SizedBox(
                              width: double.infinity,

                              child: OutlinedButton.icon(
                                onPressed: tomandoFotografia || enviandoRegistro
                                    ? null
                                    : tomarFotografia,

                                icon: tomandoFotografia
                                    ? const SizedBox(
                                        width: 18,

                                        height: 18,

                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.add_a_photo_outlined),

                                label: Text(
                                  tomandoFotografia
                                      ? 'Abriendo cámara...'
                                      : 'Agregar otra fotografía',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 30),

                    // =================================================
                    // PROGRESO
                    // =================================================
                    if (mensajeProceso != null) ...[
                      Container(
                        width: double.infinity,

                        padding: const EdgeInsets.all(14),

                        margin: const EdgeInsets.only(bottom: 14),

                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),

                          borderRadius: BorderRadius.circular(12),
                        ),

                        child: Row(
                          children: [
                            const SizedBox(
                              width: 20,

                              height: 20,

                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),

                            const SizedBox(width: 12),

                            Expanded(
                              child: Text(
                                mensajeProceso!,

                                style: const TextStyle(
                                  color: Color(0xFF1E40AF),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // =================================================
                    // ENVIAR
                    // =================================================
                    SizedBox(
                      width: double.infinity,

                      height: 56,

                      child: ElevatedButton(
                        onPressed:
                            formularioValido &&
                                !enviandoRegistro &&
                                !tomandoFotografia
                            ? enviarRegistro
                            : null,

                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),

                          foregroundColor: Colors.white,

                          disabledBackgroundColor: const Color(0xFFD1D5DB),

                          disabledForegroundColor: const Color(0xFF6B7280),

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),

                        child: enviandoRegistro
                            ? const SizedBox(
                                width: 22,

                                height: 22,

                                child: CircularProgressIndicator(
                                  strokeWidth: 2,

                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                fotografias.length <= 1
                                    ? 'Enviar registro'
                                    : 'Enviar registro con ${fotografias.length} evidencias',

                                style: const TextStyle(
                                  fontSize: 16,

                                  fontWeight: FontWeight.w600,
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
      ),
    );
  }
}

// =================================================================
// DATO DE TEXTO
// =================================================================

class _DatoTexto extends StatelessWidget {
  final String titulo;
  final String valor;

  const _DatoTexto({required this.titulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),

        const SizedBox(height: 4),

        Text(
          valor,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }
}

// =================================================================
// OPCIÓN DE ESTADO
// =================================================================

class _OpcionEstado extends StatelessWidget {
  final String titulo;
  final String descripcion;

  final IconData icono;

  final bool seleccionado;

  final VoidCallback onTap;

  const _OpcionEstado({
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: seleccionado ? const Color(0xFFEFF6FF) : Colors.white,

      borderRadius: BorderRadius.circular(14),

      child: InkWell(
        onTap: onTap,

        borderRadius: BorderRadius.circular(14),

        child: Container(
          padding: const EdgeInsets.all(18),

          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),

            border: Border.all(
              color: seleccionado
                  ? const Color(0xFF1565C0)
                  : const Color(0xFFE5E7EB),

              width: seleccionado ? 2 : 1,
            ),
          ),

          child: Row(
            children: [
              Icon(
                icono,

                size: 30,

                color: seleccionado
                    ? const Color(0xFF1565C0)
                    : const Color(0xFF6B7280),
              ),

              const SizedBox(width: 14),

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

                    const SizedBox(height: 4),

                    Text(
                      descripcion,

                      style: const TextStyle(
                        fontSize: 13,

                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),

              Icon(
                seleccionado
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,

                color: seleccionado
                    ? const Color(0xFF1565C0)
                    : const Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =================================================================
// RESUMEN DE FECHA/HORA
// =================================================================

class _DatoResumen extends StatelessWidget {
  final String titulo;
  final String valor;

  final IconData icono;

  const _DatoResumen({
    required this.titulo,
    required this.valor,
    required this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),

        borderRadius: BorderRadius.circular(12),
      ),

      child: Row(
        children: [
          Icon(icono, color: const Color(0xFF1565C0), size: 22),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  titulo,

                  style: const TextStyle(
                    fontSize: 12,

                    color: Color(0xFF6B7280),
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  valor,

                  style: const TextStyle(
                    fontSize: 15,

                    fontWeight: FontWeight.bold,

                    color: Color(0xFF1F2937),
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
