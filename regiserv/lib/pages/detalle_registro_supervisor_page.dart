import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DetalleRegistroSupervisorPage extends StatefulWidget {
  // Se deja opcional temporalmente porque esta pantalla también es
  // utilizada por Alertas. La pantalla de Registros reales sí enviará
  // este identificador.
  final int? idRegistroAseo;

  final String fecha;
  final String responsable;
  final String lugar;
  final String inicio;
  final String termino;
  final String duracion;
  final String estado;

  final String? motivoParcial;
  final String? categoriaObservacion;
  final String? detalleObservacion;
  final String? estadoAlerta;
  final bool esCobertura;

  final ValueChanged<String>? onEstadoObservacionChanged;

  const DetalleRegistroSupervisorPage({
    super.key,
    this.idRegistroAseo,
    required this.fecha,
    required this.responsable,
    required this.lugar,
    required this.inicio,
    required this.termino,
    required this.duracion,
    required this.estado,
    this.motivoParcial,
    this.categoriaObservacion,
    this.detalleObservacion,
    this.estadoAlerta,
    this.esCobertura = false,
    this.onEstadoObservacionChanged,
  });

  @override
  State<DetalleRegistroSupervisorPage> createState() =>
      _DetalleRegistroSupervisorPageState();
}

class _DetalleRegistroSupervisorPageState
    extends State<DetalleRegistroSupervisorPage> {
  SupabaseClient get supabase => Supabase.instance.client;

  String? estadoObservacion;
  String? categoriaObservacionActual;
  String? detalleObservacionActual;
  bool derivaMantencion = false;
  bool esCoberturaActual = false;

  final List<Map<String, dynamic>> evidencias = <Map<String, dynamic>>[];

  bool cargandoDetalle = false;
  bool actualizandoObservacion = false;

  String? errorDetalle;

  // =============================================================
  // INICIALIZACIÓN
  // =============================================================

  @override
  void initState() {
    super.initState();

    esCoberturaActual = widget.esCobertura;
    estadoObservacion = widget.estadoAlerta;
    categoriaObservacionActual = widget.categoriaObservacion;
    detalleObservacionActual = widget.detalleObservacion;

    // Compatibilidad con la ruta antigua de Alertas:
    // hoy "Daño a infraestructura" es una categoría que
    // deriva a Mantención.
    derivaMantencion =
        widget.categoriaObservacion?.trim() == 'Daño a infraestructura';

    if (widget.idRegistroAseo != null) {
      cargarDetalleReal();
    }
  }

  // =============================================================
  // CARGAR DETALLE REAL
  // =============================================================

  Future<void> cargarDetalleReal() async {
    final int? idRegistro = widget.idRegistroAseo;

    if (idRegistro == null) {
      return;
    }

    if (mounted) {
      setState(() {
        cargandoDetalle = true;
        errorDetalle = null;
      });
    }

    try {
      final dynamic respuesta = await supabase.rpc(
        'obtener_detalle_registro_supervision',
        params: <String, dynamic>{'p_id_registro_aseo': idRegistro},
      );

      if (respuesta is! Map) {
        throw Exception('Respuesta inválida al cargar el detalle.');
      }

      final Map<String, dynamic> datos = Map<String, dynamic>.from(respuesta);

      if (datos['ok'] != true) {
        throw Exception('No fue posible cargar el detalle.');
      }

      // El detalle se abre también desde Alertas, sin datos de la lista.
      final dynamic marcaRaw = await supabase
          .from('registro_aseo')
          .select('es_cobertura')
          .eq('id_registro_aseo', idRegistro)
          .maybeSingle();
      final bool coberturaActualizada =
          marcaRaw is Map && marcaRaw['es_cobertura'] == true;

      String? nuevoEstado = estadoObservacion;
      String? nuevaCategoria = categoriaObservacionActual;
      String? nuevoDetalle = detalleObservacionActual;
      bool nuevaDerivacionMantencion = derivaMantencion;

      final dynamic observacionRaw = datos['observacion'];

      if (observacionRaw is Map) {
        final Map<String, dynamic> observacion = Map<String, dynamic>.from(
          observacionRaw,
        );

        nuevaCategoria = observacion['categoria']?.toString();
        nuevoDetalle = observacion['detalle']?.toString();

        nuevaDerivacionMantencion = observacion['deriva_mantencion'] == true;

        final bool atendida = observacion['atendida'] == true;

        nuevoEstado = observacion['estado_alerta']?.toString();

        if (atendida && (nuevoEstado == null || nuevoEstado.trim().isEmpty)) {
          nuevoEstado = 'Atendida';
        }

        // Al abrir una observación pendiente, la marcamos realmente
        // como leída en Supabase.
        if (nuevoEstado == 'Pendiente') {
          final dynamic respuestaLectura = await supabase.rpc(
            'gestionar_observacion_supervision',
            params: <String, dynamic>{
              'p_id_registro_aseo': idRegistro,
              'p_accion': 'leer',
            },
          );

          if (respuestaLectura is Map) {
            final Map<String, dynamic> lectura = Map<String, dynamic>.from(
              respuestaLectura,
            );

            nuevoEstado = lectura['estado_alerta']?.toString() ?? 'Leída';
          } else {
            nuevoEstado = 'Leída';
          }

          widget.onEstadoObservacionChanged?.call(nuevoEstado);
        }
      }

      final List<Map<String, dynamic>> evidenciasTemporales =
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
              debugPrint('ERROR CREANDO URL FIRMADA PARA $ruta: $error');
            }
          }

          evidenciasTemporales.add(<String, dynamic>{
            ...evidencia,
            'url_firmada': urlFirmada,
          });
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        esCoberturaActual = coberturaActualizada;
        estadoObservacion = nuevoEstado;
        categoriaObservacionActual = nuevaCategoria;
        detalleObservacionActual = nuevoDetalle;
        derivaMantencion = nuevaDerivacionMantencion;

        evidencias
          ..clear()
          ..addAll(evidenciasTemporales);

        cargandoDetalle = false;
      });
    } catch (error, stackTrace) {
      debugPrint('ERROR CARGANDO DETALLE SUPERVISOR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        cargandoDetalle = false;
        errorDetalle =
            'No fue posible cargar las evidencias y el estado actualizado.';
      });
    }
  }

  // =============================================================
  // COLORES SEGÚN ESTADO DEL ASEO
  // =============================================================

  Color obtenerColorEstado() {
    switch (widget.estado) {
      case 'Completo':
        return const Color(0xFF16A34A);

      case 'Parcial':
        return const Color(0xFFD97706);

      case 'Con Observaciones':
        return const Color(0xFFDC2626);

      default:
        return const Color(0xFF6B7280);
    }
  }

  Color obtenerFondoEstado() {
    switch (widget.estado) {
      case 'Completo':
        return const Color(0xFFF0FDF4);

      case 'Parcial':
        return const Color(0xFFFFFBEB);

      case 'Con Observaciones':
        return const Color(0xFFFEF2F2);

      default:
        return const Color(0xFFF3F4F6);
    }
  }

  // =============================================================
  // COLORES SEGÚN ESTADO DE LA OBSERVACIÓN
  // =============================================================

  Color obtenerColorObservacion() {
    switch (estadoObservacion) {
      case 'Pendiente':
        return const Color(0xFFDC2626);

      case 'Leída':
      case 'En atención':
        return const Color(0xFFD97706);

      case 'Atendida':
      case 'Resuelta':
        return const Color(0xFF16A34A);

      default:
        return const Color(0xFF6B7280);
    }
  }

  Color obtenerFondoObservacion() {
    switch (estadoObservacion) {
      case 'Pendiente':
        return const Color(0xFFFEE2E2);

      case 'Leída':
      case 'En atención':
        return const Color(0xFFFFF7ED);

      case 'Atendida':
      case 'Resuelta':
        return const Color(0xFFDCFCE7);

      default:
        return const Color(0xFFF3F4F6);
    }
  }

  // =============================================================
  // MARCAR OBSERVACIÓN COMO ATENDIDA
  // =============================================================

  Future<void> marcarComoAtendida() async {
    if (actualizandoObservacion) {
      return;
    }

    if (derivaMantencion) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta observación debe ser resuelta por Mantención.'),
        ),
      );

      return;
    }

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Marcar como atendida'),
          content: const Text(
            '¿Confirmas que esta observación ya fue atendida?',
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
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
              ),
              child: const Text('Sí, marcar atendida'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      return;
    }

    final int? idRegistro = widget.idRegistroAseo;

    // Compatibilidad temporal con la pantalla antigua de Alertas.
    // Cuando migremos esa pantalla también enviará idRegistroAseo.
    if (idRegistro == null) {
      setState(() {
        estadoObservacion = 'Atendida';
      });

      widget.onEstadoObservacionChanged?.call('Atendida');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La observación fue marcada como atendida en esta vista.',
          ),
        ),
      );

      return;
    }

    setState(() {
      actualizandoObservacion = true;
    });

    try {
      final dynamic respuesta = await supabase.rpc(
        'gestionar_observacion_supervision',
        params: <String, dynamic>{
          'p_id_registro_aseo': idRegistro,
          'p_accion': 'atender',
        },
      );

      if (respuesta is! Map) {
        throw Exception('Respuesta inválida al actualizar la observación.');
      }

      final Map<String, dynamic> resultado = Map<String, dynamic>.from(
        respuesta,
      );

      if (resultado['ok'] != true) {
        throw Exception('No fue posible actualizar la observación.');
      }

      final String nuevoEstado =
          resultado['estado_alerta']?.toString() ?? 'Atendida';

      if (!mounted) {
        return;
      }

      setState(() {
        estadoObservacion = nuevoEstado;
        actualizandoObservacion = false;
      });

      widget.onEstadoObservacionChanged?.call(nuevoEstado);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La observación fue marcada como atendida.'),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('ERROR MARCANDO OBSERVACIÓN COMO ATENDIDA: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        actualizandoObservacion = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible actualizar la observación: $error'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  // =============================================================
  // VER FOTO COMPLETA
  // =============================================================

  void mostrarFotografia(String url, String nombre) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Image.network(
                  url,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox(
                      height: 300,
                      child: Center(
                        child: Text(
                          'No fue posible mostrar la fotografía.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final Color colorEstado = obtenerColorEstado();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Detalle del registro',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        actions: [
          if (widget.idRegistroAseo != null)
            IconButton(
              tooltip: 'Actualizar',
              onPressed: cargandoDetalle ? null : cargarDetalleReal,
              icon: const Icon(Icons.refresh),
            ),
        ],
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: obtenerFondoEstado(),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.estado,
                      style: TextStyle(
                        color: colorEstado,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  if (esCoberturaActual) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Labor realizada por Auxiliar no asignado',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // =================================================
                  // INFORMACIÓN DE LA LABOR
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
                          'Información de la labor',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 20),

                        if (widget.idRegistroAseo != null)
                          _DatoDetalleSupervisor(
                            titulo: 'Registro',
                            valor: '#${widget.idRegistroAseo}',
                            icono: Icons.tag_outlined,
                          ),

                        _DatoDetalleSupervisor(
                          titulo: 'Responsable',
                          valor: widget.responsable,
                          icono: Icons.person_outline,
                        ),

                        _DatoDetalleSupervisor(
                          titulo: 'Lugar',
                          valor: widget.lugar,
                          icono: Icons.location_on_outlined,
                        ),

                        _DatoDetalleSupervisor(
                          titulo: 'Fecha',
                          valor: widget.fecha,
                          icono: Icons.calendar_today_outlined,
                          mostrarSeparador: false,
                        ),

                        const Divider(height: 30),

                        Row(
                          children: [
                            Expanded(
                              child: _DatoTiempoSupervisor(
                                titulo: 'Inicio',
                                valor: widget.inicio,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _DatoTiempoSupervisor(
                                titulo: 'Término',
                                valor: widget.termino,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        _DatoDetalleSupervisor(
                          titulo: 'Duración',
                          valor: widget.duracion,
                          icono: Icons.timer_outlined,
                          mostrarSeparador: false,
                        ),
                      ],
                    ),
                  ),

                  // =================================================
                  // REGISTRO PARCIAL
                  // =================================================
                  if (widget.estado == 'Parcial' &&
                      widget.motivoParcial != null &&
                      widget.motivoParcial!.trim().isNotEmpty) ...[
                    const SizedBox(height: 18),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Color(0xFFD97706),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Motivo del registro parcial',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.motivoParcial!,
                            style: const TextStyle(
                              color: Color(0xFF78350F),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // =================================================
                  // OBSERVACIÓN
                  // =================================================
                  if (widget.estado == 'Con Observaciones') ...[
                    const SizedBox(height: 18),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFDC2626),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Observación',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF991B1B),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          _DatoObservacion(
                            titulo: 'Categoría',
                            valor:
                                categoriaObservacionActual ?? 'Sin categoría',
                          ),

                          const SizedBox(height: 14),

                          _DatoObservacion(
                            titulo: 'Detalle',
                            valor: detalleObservacionActual ?? 'Sin detalle',
                          ),

                          if (estadoObservacion != null) ...[
                            const SizedBox(height: 20),
                            const Divider(color: Color(0xFFFECACA)),
                            const SizedBox(height: 16),

                            Row(
                              children: [
                                const Text(
                                  'Estado:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF991B1B),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: obtenerFondoObservacion(),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    estadoObservacion!,
                                    style: TextStyle(
                                      color: obtenerColorObservacion(),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),

                            if (derivaMantencion &&
                                estadoObservacion != 'Resuelta')
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
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.engineering_outlined,
                                      color: Color(0xFF2563EB),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        estadoObservacion == 'En atención'
                                            ? 'Esta incidencia está siendo atendida por Mantención. El cierre corresponde al equipo técnico.'
                                            : 'Esta observación fue derivada a Mantención. El cierre corresponde al equipo técnico.',
                                        style: const TextStyle(
                                          color: Color(0xFF1E40AF),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (derivaMantencion &&
                                estadoObservacion == 'Resuelta')
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.task_alt,
                                      color: Color(0xFF16A34A),
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Incidencia resuelta por Mantención',
                                        style: TextStyle(
                                          color: Color(0xFF166534),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (estadoObservacion != 'Atendida' &&
                                estadoObservacion != 'Resuelta')
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: actualizandoObservacion
                                      ? null
                                      : marcarComoAtendida,
                                  icon: actualizandoObservacion
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.check_circle_outline),
                                  label: Text(
                                    actualizandoObservacion
                                        ? 'Actualizando...'
                                        : 'Marcar como atendida',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF16A34A),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Color(0xFF16A34A),
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Observación atendida',
                                        style: TextStyle(
                                          color: Color(0xFF166534),
                                          fontWeight: FontWeight.w600,
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
                  ],

                  const SizedBox(height: 18),

                  // =================================================
                  // EVIDENCIAS FOTOGRÁFICAS
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
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Evidencia fotográfica',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                            ),
                            if (evidencias.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${evidencias.length} ${evidencias.length == 1 ? 'foto' : 'fotos'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1565C0),
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        if (widget.idRegistroAseo == null)
                          _MensajeEvidencia(
                            icono: Icons.info_outline,
                            texto: 'La evidencia real se mostrará cuando esta pantalla se abra desde un registro conectado a Supabase.',
                          )
                        else if (cargandoDetalle && evidencias.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(28),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (errorDetalle != null && evidencias.isEmpty)
                          Column(
                            children: [
                              _MensajeEvidencia(
                                icono: Icons.cloud_off_outlined,
                                texto: errorDetalle!,
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: cargarDetalleReal,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reintentar'),
                              ),
                            ],
                          )
                        else if (evidencias.isEmpty)
                          const _MensajeEvidencia(
                            icono: Icons.photo_outlined,
                            texto:
                                'Este registro no tiene fotografías asociadas.',
                          )
                        else
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final int columnas = constraints.maxWidth >= 520
                                  ? 3
                                  : 2;

                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
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

                                  final String? url = evidencia['url_firmada']
                                      ?.toString();

                                  final String nombre =
                                      evidencia['nombre_archivo']?.toString() ??
                                      'Fotografía ${index + 1}';

                                  return _TarjetaEvidencia(
                                    url: url,
                                    nombre: nombre,
                                    onTap: url == null
                                        ? null
                                        : () {
                                            mostrarFotografia(url, nombre);
                                          },
                                  );
                                },
                              );
                            },
                          ),

                        if (errorDetalle != null && evidencias.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            errorDetalle!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ],
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
// DATO GENERAL
// =================================================================

class _DatoDetalleSupervisor extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icono;
  final bool mostrarSeparador;

  const _DatoDetalleSupervisor({
    required this.titulo,
    required this.valor,
    required this.icono,
    this.mostrarSeparador = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, size: 21, color: const Color(0xFF1565C0)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    valor,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (mostrarSeparador) ...[
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

// =================================================================
// INICIO / TÉRMINO
// =================================================================

class _DatoTiempoSupervisor extends StatelessWidget {
  final String titulo;
  final String valor;

  const _DatoTiempoSupervisor({required this.titulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// OBSERVACIÓN
// =================================================================

class _DatoObservacion extends StatelessWidget {
  final String titulo;
  final String valor;

  const _DatoObservacion({required this.titulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B)),
        ),
        const SizedBox(height: 4),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF7F1D1D),
          ),
        ),
      ],
    );
  }
}

// =================================================================
// MENSAJE DE EVIDENCIA
// =================================================================

class _MensajeEvidencia extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _MensajeEvidencia({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Icon(icono, size: 42, color: const Color(0xFF6B7280)),
          const SizedBox(height: 10),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// TARJETA DE EVIDENCIA
// =================================================================

class _TarjetaEvidencia extends StatelessWidget {
  final String? url;
  final String nombre;
  final VoidCallback? onTap;

  const _TarjetaEvidencia({
    required this.url,
    required this.nombre,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: url == null
              ? const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 40,
                    color: Color(0xFF9CA3AF),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      url!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 40,
                            color: Color(0xFF9CA3AF),
                          ),
                        );
                      },
                    ),
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
