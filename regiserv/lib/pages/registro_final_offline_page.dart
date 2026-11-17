import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/labor/labor_context.dart';
import '../core/storage/hive_local_storage.dart';

import 'auxiliar_home_page.dart';

class RegistroFinalOfflinePage extends StatefulWidget {
  final LaborContext labor;

  const RegistroFinalOfflinePage({super.key, required this.labor});

  @override
  State<RegistroFinalOfflinePage> createState() =>
      _RegistroFinalOfflinePageState();
}

class _RegistroFinalOfflinePageState extends State<RegistroFinalOfflinePage> {
  final ImagePicker _picker = ImagePicker();

  final TextEditingController motivoParcialController = TextEditingController();

  final TextEditingController detalleObservacionController =
      TextEditingController();

  final List<_FotoPendiente> fotos = <_FotoPendiente>[];

  final List<String> estados = <String>[
    'Completo',
    'Parcial',
    'Con Observaciones',
  ];

  final List<String> categorias = <String>[];

  String? estadoSeleccionado;
  String? categoriaSeleccionada;

  bool guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarCategoriasDesdeCache();
  }

  @override
  void dispose() {
    motivoParcialController.dispose();
    detalleObservacionController.dispose();
    super.dispose();
  }

  void _cargarCategoriasDesdeCache() {
    final Map<String, dynamic>? cache = HiveLocalStorage.instance
        .obtenerCacheOperacional(widget.labor.idUsuario);

    final dynamic raw = cache?['tipos_observacion'];

    final List<String> encontrados = <String>[];

    if (raw is List) {
      for (final dynamic item in raw) {
        if (item is! Map) {
          continue;
        }

        if (item['activo'] == false) {
          continue;
        }

        final String nombre = (item['nombre'] ?? '').toString().trim();

        if (nombre.isNotEmpty) {
          encontrados.add(nombre);
        }
      }
    }

    if (encontrados.isEmpty) {
      encontrados.addAll(<String>[
        'Daño a infraestructura',
        'Falta de insumos',
        'Problema de limpieza',
        'Otro',
      ]);
    }

    categorias
      ..clear()
      ..addAll(encontrados);
  }

  bool get formularioValido {
    if (estadoSeleccionado == null) {
      return false;
    }

    if (fotos.isEmpty) {
      return false;
    }

    if (estadoSeleccionado == 'Parcial' &&
        motivoParcialController.text.trim().isEmpty) {
      return false;
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

  String formatearHora(DateTime fecha) {
    final DateTime local = fecha.toLocal();

    final String hora = local.hour.toString().padLeft(2, '0');

    final String minuto = local.minute.toString().padLeft(2, '0');

    return '$hora:$minuto';
  }

  String obtenerDuracion() {
    final DateTime inicio = widget.labor.fechaHoraInicio.toLocal();

    final DateTime termino = (widget.labor.fechaHoraFin ?? DateTime.now())
        .toLocal();

    final Duration duracion = termino.difference(inicio);

    return '${duracion.inMinutes} min';
  }

  Future<void> tomarFoto() async {
    try {
      final XFile? archivo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 70,
      );

      if (archivo == null) {
        return;
      }

      final Uint8List bytes = await archivo.readAsBytes();

      const int maxBytes = 10 * 1024 * 1024;

      if (bytes.lengthInBytes > maxBytes) {
        if (!mounted) {
          return;
        }

        _mostrarMensaje(
          'La fotografía supera el máximo de 10 MB.',
          error: true,
        );

        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        fotos.add(
          _FotoPendiente(
            nombre: archivo.name.isNotEmpty
                ? archivo.name
                : 'foto_${DateTime.now().microsecondsSinceEpoch}.jpg',
            mimeType: archivo.mimeType ?? _mimeDesdeNombre(archivo.name),
            bytes: bytes,
            fechaFotografia: DateTime.now(),
          ),
        );
      });
    } catch (error) {
      debugPrint('ERROR TOMANDO FOTO OFFLINE: $error');

      if (!mounted) {
        return;
      }

      _mostrarMensaje('No fue posible tomar la fotografía.', error: true);
    }
  }

  String _mimeDesdeNombre(String nombre) {
    final String lower = nombre.toLowerCase();

    if (lower.endsWith('.png')) {
      return 'image/png';
    }

    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }

    return 'image/jpeg';
  }

  void eliminarFoto(int index) {
    setState(() {
      fotos.removeAt(index);
    });
  }

  Future<void> guardarPendiente() async {
    if (!formularioValido || guardando) {
      return;
    }

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('¿Guardar registro?'),
          content: const Text(
            'El registro quedará guardado en este dispositivo como pendiente de sincronización y se enviará cuando vuelva la conexión.',
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
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      return;
    }

    setState(() {
      guardando = true;
    });

    try {
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

      final Map<String, dynamic> payload = <String, dynamic>{
        ...widget.labor.toMap(),
        'id_local_labor': widget.labor.idLocal,
        'estado_aseo': estadoSeleccionado,
        'comentario': comentario,
        'tipo_observacion': tipoObservacion,
        'detalle_observacion': detalleObservacion,
        'estado_sincronizacion': 'Pendiente',
        'fecha_registro_final': DateTime.now().toUtc().toIso8601String(),
      };

      final List<Map<String, dynamic>> evidencias = fotos
          .map(
            (foto) => <String, dynamic>{
              'nombre_archivo': foto.nombre,
              'mime_type': foto.mimeType,
              'fecha_fotografia': foto.fechaFotografia
                  .toUtc()
                  .toIso8601String(),
              'bytes_base64': base64Encode(foto.bytes),
            },
          )
          .toList();

      await HiveLocalStorage.instance.agregarPendiente(
        idUsuario: widget.labor.idUsuario,
        tipo: 'registro_aseo_completo',
        payload: payload,
        evidencias: evidencias,
      );

      // La labor ya está completamente cerrada de forma local.
      // Liberamos "labor en curso", pero NO eliminamos la cola.
      await HiveLocalStorage.instance.eliminarLaborEnCurso(
        widget.labor.idUsuario,
      );

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            icon: const Icon(
              Icons.cloud_upload_outlined,
              size: 48,
              color: Color(0xFFD97706),
            ),
            title: const Text(
              'Pendiente de sincronización',
              textAlign: TextAlign.center,
            ),
            content: const Text(
              'El registro y sus fotografías quedaron guardados localmente. RegiServ los enviará cuando vuelva la conexión.',
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

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AuxiliarHomePage()),
        (route) => false,
      );
    } catch (error, stackTrace) {
      debugPrint('ERROR GUARDANDO REGISTRO OFFLINE: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      _mostrarMensaje(
        'No fue posible guardar el registro localmente.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          guardando = false;
        });
      }
    }
  }

  void _mostrarMensaje(String mensaje, {bool error = false}) {
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

  @override
  Widget build(BuildContext context) {
    final DateTime horaTermino = (widget.labor.fechaHoraFin ?? DateTime.now())
        .toLocal();

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
                constraints: const BoxConstraints(maxWidth: 650),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.cloud_off_outlined,
                            color: Color(0xFFD97706),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Modo offline · El registro quedará pendiente de sincronización',
                              style: TextStyle(
                                color: Color(0xFF92400E),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _TarjetaResumen(
                      lugar: widget.labor.lugar,
                      auxiliar: widget.labor.nombreAuxiliar,
                      inicio: formatearHora(widget.labor.fechaHoraInicio),
                      termino: formatearHora(horaTermino),
                      duracion: obtenerDuracion(),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Resultado de la labor',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: estadoSeleccionado,
                      decoration: const InputDecoration(
                        labelText: 'Estado del aseo',
                        border: OutlineInputBorder(),
                      ),
                      items: estados
                          .map(
                            (estado) => DropdownMenuItem<String>(
                              value: estado,
                              child: Text(estado),
                            ),
                          )
                          .toList(),
                      onChanged: (valor) {
                        setState(() {
                          estadoSeleccionado = valor;

                          if (valor != 'Con Observaciones') {
                            categoriaSeleccionada = null;
                            detalleObservacionController.clear();
                          }

                          if (valor != 'Parcial') {
                            motivoParcialController.clear();
                          }
                        });
                      },
                    ),
                    if (estadoSeleccionado == 'Parcial') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: motivoParcialController,
                        maxLines: 3,
                        onChanged: (_) {
                          setState(() {});
                        },
                        decoration: const InputDecoration(
                          labelText: 'Motivo de labor parcial',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (estadoSeleccionado == 'Con Observaciones') ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: categoriaSeleccionada,
                        decoration: const InputDecoration(
                          labelText: 'Categoría de observación',
                          border: OutlineInputBorder(),
                        ),
                        items: categorias
                            .map(
                              (categoria) => DropdownMenuItem<String>(
                                value: categoria,
                                child: Text(categoria),
                              ),
                            )
                            .toList(),
                        onChanged: (valor) {
                          setState(() {
                            categoriaSeleccionada = valor;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: detalleObservacionController,
                        maxLines: 4,
                        onChanged: (_) {
                          setState(() {});
                        },
                        decoration: const InputDecoration(
                          labelText: 'Detalle de la observación',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    const Text(
                      'Evidencias fotográficas',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Debes tomar al menos una fotografía. Puedes agregar varias y eliminar cualquiera antes de guardar.',
                      style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: guardando ? null : tomarFoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Tomar fotografía'),
                      ),
                    ),
                    if (fotos.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                        itemCount: fotos.length,
                        itemBuilder: (context, index) {
                          final _FotoPendiente foto = fotos[index];

                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  foto.bytes,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Material(
                                  color: Colors.black54,
                                  shape: const CircleBorder(),
                                  child: IconButton(
                                    tooltip: 'Eliminar',
                                    onPressed: guardando
                                        ? null
                                        : () => eliminarFoto(index),
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: formularioValido && !guardando
                            ? guardarPendiente
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFD1D5DB),
                        ),
                        child: guardando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Guardar registro',
                                style: TextStyle(
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

class _FotoPendiente {
  final String nombre;
  final String mimeType;
  final Uint8List bytes;
  final DateTime fechaFotografia;

  const _FotoPendiente({
    required this.nombre,
    required this.mimeType,
    required this.bytes,
    required this.fechaFotografia,
  });
}

class _TarjetaResumen extends StatelessWidget {
  final String lugar;
  final String auxiliar;
  final String inicio;
  final String termino;
  final String duracion;

  const _TarjetaResumen({
    required this.lugar,
    required this.auxiliar,
    required this.inicio,
    required this.termino,
    required this.duracion,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lugar,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 12),
          Text('Auxiliar: $auxiliar'),
          const SizedBox(height: 6),
          Text('Inicio: $inicio'),
          const SizedBox(height: 6),
          Text('Término: $termino'),
          const SizedBox(height: 6),
          Text(
            'Duración: $duracion',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
