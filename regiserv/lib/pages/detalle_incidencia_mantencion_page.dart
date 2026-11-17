import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DetalleIncidenciaMantencionPage extends StatefulWidget {
  final int idAlerta;

  const DetalleIncidenciaMantencionPage({super.key, required this.idAlerta});

  @override
  State<DetalleIncidenciaMantencionPage> createState() =>
      _DetalleIncidenciaMantencionPageState();
}

class _DetalleIncidenciaMantencionPageState
    extends State<DetalleIncidenciaMantencionPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  Map<String, dynamic>? detalle;
  final List<Map<String, dynamic>> evidencias = <Map<String, dynamic>>[];

  bool cargando = true;
  bool tomandoIncidencia = false;
  bool resolviendoIncidencia = false;
  String? mensajeError;

  @override
  void initState() {
    super.initState();
    cargarDetalle();
  }

  String _texto(dynamic valor, {String defecto = '—'}) {
    if (valor == null) {
      return defecto;
    }

    final String texto = valor.toString().trim();

    return texto.isEmpty ? defecto : texto;
  }

  DateTime? _fecha(dynamic valor) {
    if (valor == null) {
      return null;
    }

    try {
      return DateTime.parse(valor.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _fechaHora(dynamic valor) {
    final DateTime? fecha = _fecha(valor);

    if (fecha == null) {
      return '—';
    }

    final String dia = fecha.day.toString().padLeft(2, '0');
    final String mes = fecha.month.toString().padLeft(2, '0');
    final String hora = fecha.hour.toString().padLeft(2, '0');
    final String minuto = fecha.minute.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year} $hora:$minuto';
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'En atención':
        return const Color(0xFF2563EB);
      case 'Resuelta':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFFD97706);
    }
  }

  Color _fondoEstado(String estado) {
    switch (estado) {
      case 'En atención':
        return const Color(0xFFEFF6FF);
      case 'Resuelta':
        return const Color(0xFFF0FDF4);
      default:
        return const Color(0xFFFFFBEB);
    }
  }

  Future<void> cargarDetalle() async {
    if (!mounted) {
      return;
    }

    setState(() {
      cargando = true;
      mensajeError = null;
    });

    try {
      final dynamic respuesta = await supabase.rpc(
        'obtener_detalle_incidencia_mantencion',
        params: <String, dynamic>{'p_id_alerta': widget.idAlerta},
      );

      if (respuesta is! Map) {
        throw Exception('Respuesta inválida del servidor.');
      }

      final Map<String, dynamic> datos = Map<String, dynamic>.from(respuesta);

      final List<Map<String, dynamic>> nuevasEvidencias =
          <Map<String, dynamic>>[];

      final dynamic evidenciasRaw = datos['evidencias'];

      if (evidenciasRaw is List) {
        for (final dynamic item in evidenciasRaw) {
          if (item is! Map) {
            continue;
          }

          final Map<String, dynamic> evidencia = Map<String, dynamic>.from(
            item,
          );

          final String ruta =
              evidencia['ruta_archivo']?.toString().trim() ?? '';

          String? urlFirmada;

          if (ruta.isNotEmpty) {
            try {
              urlFirmada = await supabase.storage
                  .from('evidencias-aseo')
                  .createSignedUrl(ruta, 3600);
            } catch (error) {
              debugPrint('ERROR URL FIRMADA MANTENCIÓN ($ruta): $error');
            }
          }

          nuevasEvidencias.add(<String, dynamic>{
            ...evidencia,
            'url_firmada': urlFirmada,
          });
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        detalle = datos;
        evidencias
          ..clear()
          ..addAll(nuevasEvidencias);

        cargando = false;
        mensajeError = null;
      });
    } catch (error, stackTrace) {
      debugPrint('ERROR cargarDetalleIncidenciaMantencion: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        detalle = null;
        evidencias.clear();
        cargando = false;
        mensajeError = 'No fue posible cargar el detalle de la incidencia.';
      });
    }
  }

  Future<void> tomarIncidencia() async {
    if (tomandoIncidencia) {
      return;
    }

    final Map<String, dynamic>? datos = detalle;

    if (datos == null) {
      return;
    }

    final String estadoActual = _texto(
      datos['estado_alerta'],
      defecto: 'Pendiente',
    );

    if (estadoActual == 'En atención' || estadoActual == 'Resuelta') {
      return;
    }

    setState(() {
      tomandoIncidencia = true;
    });

    try {
      await supabase.rpc(
        'gestionar_incidencia_mantencion',
        params: <String, dynamic>{
          'p_id_alerta': widget.idAlerta,
          'p_accion': 'tomar',
          'p_comentario': null,
        },
      );

      await cargarDetalle();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Incidencia tomada correctamente. '
            'Ahora se encuentra En atención.',
          ),
        ),
      );
    } catch (error) {
      debugPrint('ERROR tomarIncidencia Mantención: $error');

      if (!mounted) {
        return;
      }

      final String mensaje =
          error.toString().contains(
            'La incidencia ya está siendo atendida por otro técnico',
          )
          ? 'La incidencia ya está siendo atendida por otro técnico.'
          : 'No fue posible tomar la incidencia.';

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensaje)));

      await cargarDetalle();
    } finally {
      if (mounted) {
        setState(() {
          tomandoIncidencia = false;
        });
      }
    }
  }

  Future<String?> solicitarComentarioResolucion() async {
    final TextEditingController comentarioController = TextEditingController();

    bool mostrarError = false;

    final String? comentario = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Resolver incidencia'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Describe brevemente la solución realizada. '
                      'Este comentario quedará registrado en la incidencia.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: comentarioController,
                      autofocus: true,
                      maxLines: 5,
                      minLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Solución realizada',
                        hintText: 'Ej.: Se reemplazó la llave del lavamanos y se verificó su funcionamiento.',
                        border: const OutlineInputBorder(),
                        errorText: mostrarError
                            ? 'Debes indicar la solución realizada.'
                            : null,
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
                FilledButton(
                  onPressed: () {
                    final String texto = comentarioController.text.trim();

                    if (texto.isEmpty) {
                      setStateDialog(() {
                        mostrarError = true;
                      });
                      return;
                    }

                    Navigator.pop(context, texto);
                  },
                  child: const Text('Confirmar resolución'),
                ),
              ],
            );
          },
        );
      },
    );

    comentarioController.dispose();

    return comentario;
  }

  Future<void> resolverIncidencia() async {
    if (resolviendoIncidencia) {
      return;
    }

    final Map<String, dynamic>? datos = detalle;

    if (datos == null) {
      return;
    }

    final String estadoActual = _texto(
      datos['estado_alerta'],
      defecto: 'Pendiente',
    );

    if (estadoActual != 'En atención') {
      return;
    }

    final String? idUsuarioActual = supabase.auth.currentUser?.id;

    final String idUsuarioAsignado =
        datos['id_usuario_asignado']?.toString().trim() ?? '';

    if (idUsuarioActual == null || idUsuarioAsignado != idUsuarioActual) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solo el técnico que tomó la incidencia puede resolverla.',
          ),
        ),
      );

      return;
    }

    final String? comentario = await solicitarComentarioResolucion();

    if (comentario == null || comentario.trim().isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      resolviendoIncidencia = true;
    });

    try {
      await supabase.rpc(
        'gestionar_incidencia_mantencion',
        params: <String, dynamic>{
          'p_id_alerta': widget.idAlerta,
          'p_accion': 'resolver',
          'p_comentario': comentario.trim(),
        },
      );

      await cargarDetalle();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incidencia resuelta correctamente.')),
      );
    } catch (error) {
      debugPrint('ERROR resolverIncidencia Mantención: $error');

      if (!mounted) {
        return;
      }

      String mensaje = 'No fue posible resolver la incidencia.';

      final String textoError = error.toString();

      if (textoError.contains(
        'Solo el técnico que tomó la incidencia puede resolverla',
      )) {
        mensaje = 'Solo el técnico que tomó la incidencia puede resolverla.';
      } else if (textoError.contains(
        'Primero debes poner la incidencia En atención',
      )) {
        mensaje = 'La incidencia ya no se encuentra En atención.';
      } else if (textoError.contains(
        'La incidencia ya se encuentra resuelta',
      )) {
        mensaje = 'La incidencia ya se encuentra resuelta.';
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensaje)));

      await cargarDetalle();
    } finally {
      if (mounted) {
        setState(() {
          resolviendoIncidencia = false;
        });
      }
    }
  }

  void mostrarFotografia(String url, String nombre) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                automaticallyImplyLeading: false,
                title: Text(nombre, style: const TextStyle(fontSize: 16)),
                actions: [
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Flexible(
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        return child;
                      }

                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No fue posible mostrar la fotografía.',
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _seccion({required String titulo, required List<Widget> hijos}) {
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
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 14),
          ...hijos,
        ],
      ),
    );
  }

  Widget _dato(String titulo, String valor, {IconData? icono}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 19, color: const Color(0xFF6B7280)),
            const SizedBox(width: 9),
          ],
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
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? datos = detalle;

    final String estado = datos == null
        ? 'Pendiente'
        : _texto(datos['estado_alerta'], defecto: 'Pendiente');

    final String? idUsuarioActual = supabase.auth.currentUser?.id;

    final String idUsuarioAsignado =
        datos?['id_usuario_asignado']?.toString().trim() ?? '';

    final bool incidenciaPropia =
        idUsuarioActual != null && idUsuarioAsignado == idUsuarioActual;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Detalle de incidencia',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        actions: [
          IconButton(
            onPressed: cargando ? null : cargarDetalle,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: cargarDetalle,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 700),
                child: cargando
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : mensajeError != null
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 44,
                              color: Color(0xFFDC2626),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              mensajeError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF991B1B)),
                            ),
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                              onPressed: cargarDetalle,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      )
                    : datos == null
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _texto(
                                    datos['categoria_observacion'],
                                    defecto: 'Daño a infraestructura',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: _fondoEstado(estado),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  estado,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _colorEstado(estado),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 22),

                          if (estado != 'En atención' &&
                              estado != 'Resuelta') ...[
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: tomandoIncidencia
                                    ? null
                                    : tomarIncidencia,
                                icon: tomandoIncidencia
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.engineering_outlined),
                                label: Text(
                                  tomandoIncidencia
                                      ? 'Tomando incidencia...'
                                      : 'Tomar incidencia',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1565C0),
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: const Color(
                                    0xFF93C5FD,
                                  ),
                                  disabledForegroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),
                          ],

                          if (estado == 'En atención' && incidenciaPropia) ...[
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: resolviendoIncidencia
                                    ? null
                                    : resolverIncidencia,
                                icon: resolviendoIncidencia
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.task_alt_outlined),
                                label: Text(
                                  resolviendoIncidencia
                                      ? 'Resolviendo incidencia...'
                                      : 'Resolver incidencia',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF16A34A),
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: const Color(
                                    0xFF86EFAC,
                                  ),
                                  disabledForegroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),
                          ],

                          if (estado == 'En atención' && !incidenciaPropia) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFBFDBFE),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Color(0xFF2563EB),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Esta incidencia está siendo atendida por otro técnico de Mantención.',
                                      style: TextStyle(
                                        color: Color(0xFF1E40AF),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 18),
                          ],

                          _seccion(
                            titulo: 'Incidencia',
                            hijos: [
                              _dato(
                                'Descripción',
                                _texto(
                                  datos['detalle_observacion'],
                                  defecto: 'Sin detalle',
                                ),
                                icono: Icons.description_outlined,
                              ),
                              _dato(
                                'Reportada',
                                _fechaHora(datos['fecha_alerta']),
                                icono: Icons.schedule_outlined,
                              ),
                              _dato(
                                'Reportada por',
                                _texto(
                                  datos['responsable'],
                                  defecto: 'Usuario no identificado',
                                ),
                                icono: Icons.person_outline,
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          _seccion(
                            titulo: 'Ubicación',
                            hijos: [
                              _dato(
                                'Sede',
                                _texto(datos['sede']),
                                icono: Icons.location_city_outlined,
                              ),
                              _dato(
                                'Edificio',
                                _texto(datos['edificio']),
                                icono: Icons.apartment_outlined,
                              ),
                              _dato(
                                'Piso',
                                datos['numero_nivel'] == null
                                    ? '—'
                                    : 'Piso ${datos['numero_nivel']}',
                                icono: Icons.layers_outlined,
                              ),
                              _dato(
                                'Espacio',
                                _texto(
                                  datos['espacio_nombre'],
                                  defecto: _texto(datos['espacio_codigo']),
                                ),
                                icono: Icons.meeting_room_outlined,
                              ),
                              _dato(
                                'Tipo de espacio',
                                _texto(datos['tipo_espacio']),
                                icono: Icons.category_outlined,
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          _seccion(
                            titulo: 'Gestión de Mantención',
                            hijos: [
                              _dato(
                                'Técnico asignado',
                                _texto(
                                  datos['tecnico_asignado'],
                                  defecto: 'Sin asignar',
                                ),
                                icono: Icons.engineering_outlined,
                              ),
                              _dato(
                                'Inicio de atención',
                                _fechaHora(datos['fecha_inicio_atencion']),
                                icono: Icons.play_circle_outline,
                              ),
                              _dato(
                                'Fecha de resolución',
                                _fechaHora(datos['fecha_resolucion']),
                                icono: Icons.task_alt_outlined,
                              ),
                              if (_texto(
                                datos['comentario_resolucion'],
                                defecto: '',
                              ).isNotEmpty)
                                _dato(
                                  'Solución / comentario',
                                  _texto(datos['comentario_resolucion']),
                                  icono: Icons.notes_outlined,
                                ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          _seccion(
                            titulo: 'Evidencias',
                            hijos: [
                              if (evidencias.isEmpty)
                                const Text(
                                  'Esta incidencia no tiene fotografías disponibles.',
                                  style: TextStyle(color: Color(0xFF6B7280)),
                                )
                              else
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final int columnas =
                                        constraints.maxWidth > 520 ? 3 : 2;

                                    return GridView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: evidencias.length,
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: columnas,
                                            crossAxisSpacing: 10,
                                            mainAxisSpacing: 10,
                                            childAspectRatio: 1,
                                          ),
                                      itemBuilder: (context, index) {
                                        final Map<String, dynamic> evidencia =
                                            evidencias[index];

                                        final String? url =
                                            evidencia['url_firmada']
                                                ?.toString();

                                        final String nombre = _texto(
                                          evidencia['nombre_archivo'],
                                          defecto: 'Fotografía ${index + 1}',
                                        );

                                        return InkWell(
                                          onTap: url == null
                                              ? null
                                              : () {
                                                  mostrarFotografia(
                                                    url,
                                                    nombre,
                                                  );
                                                },
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Container(
                                            clipBehavior: Clip.antiAlias,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF3F4F6),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: const Color(0xFFE5E7EB),
                                              ),
                                            ),
                                            child: url == null
                                                ? const Center(
                                                    child: Icon(
                                                      Icons
                                                          .broken_image_outlined,
                                                      color: Color(0xFF9CA3AF),
                                                    ),
                                                  )
                                                : Image.network(
                                                    url,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) {
                                                          return const Center(
                                                            child: Icon(
                                                              Icons
                                                                  .broken_image_outlined,
                                                              color: Color(
                                                                0xFF9CA3AF,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                  ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                            ],
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
