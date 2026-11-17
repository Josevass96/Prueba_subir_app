import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DetalleSolicitudExcepcionPage extends StatefulWidget {
  final int idAlerta;
  final int idRegistroAseo;

  final String fecha;
  final String horaSolicitud;
  final String lugar;
  final String responsable;
  final String inicio;
  final String motivo;
  final String detalle;
  final String estadoInicial;

  const DetalleSolicitudExcepcionPage({
    super.key,
    required this.idAlerta,
    required this.idRegistroAseo,
    required this.fecha,
    required this.horaSolicitud,
    required this.lugar,
    required this.responsable,
    required this.inicio,
    required this.motivo,
    required this.detalle,
    required this.estadoInicial,
  });

  @override
  State<DetalleSolicitudExcepcionPage> createState() =>
      _DetalleSolicitudExcepcionPageState();
}

class _DetalleSolicitudExcepcionPageState
    extends State<DetalleSolicitudExcepcionPage> {
  SupabaseClient get supabase => Supabase.instance.client;

  String estadoSolicitud = 'Pendiente';

  bool actualizandoEstado = false;
  bool resolviendo = false;

  @override
  void initState() {
    super.initState();

    estadoSolicitud = widget.estadoInicial;

    marcarComoLeida();
  }

  // =============================================================
  // MARCAR COMO LEÍDA
  // =============================================================

  Future<void> marcarComoLeida() async {
    if (estadoSolicitud != 'Pendiente' || actualizandoEstado) {
      return;
    }

    actualizandoEstado = true;

    try {
      final dynamic respuesta = await supabase.rpc(
        'marcar_solicitud_cierre_leida',
        params: <String, dynamic>{'p_id_alerta': widget.idAlerta},
      );

      if (respuesta is Map && mounted) {
        final Map<String, dynamic> resultado = Map<String, dynamic>.from(
          respuesta,
        );

        setState(() {
          estadoSolicitud = resultado['estado']?.toString() ?? 'Leída';
        });
      }
    } catch (error) {
      debugPrint('ERROR MARCANDO SOLICITUD COMO LEÍDA: $error');
    } finally {
      actualizandoEstado = false;
    }
  }

  // =============================================================
  // SOLICITAR COMENTARIO
  // =============================================================

  Future<String?> pedirComentario({required bool aprobar}) async {
    final TextEditingController controller = TextEditingController();

    final String? comentario = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            aprobar ? 'Aprobar cierre excepcional' : 'Rechazar solicitud',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                aprobar
                    ? 'Ingresa un comentario breve que deje constancia de la autorización.'
                    : 'Indica por qué se rechaza la solicitud. La labor volverá a quedar abierta.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                minLines: 3,
                decoration: InputDecoration(
                  labelText: 'Comentario *',
                  hintText: aprobar
                      ? 'Ej.: Se autoriza cierre por falla del NFC.'
                      : 'Ej.: Debe intentar nuevamente la validación.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final String texto = controller.text.trim();

                if (texto.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Debes ingresar un comentario.'),
                    ),
                  );

                  return;
                }

                Navigator.pop(context, texto);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: aprobar
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              child: Text(aprobar ? 'Aprobar' : 'Rechazar'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    return comentario;
  }

  // =============================================================
  // RESOLVER
  // =============================================================

  Future<void> resolver({required bool aprobar}) async {
    if (resolviendo) {
      return;
    }

    final String? comentario = await pedirComentario(aprobar: aprobar);

    if (comentario == null || !mounted) {
      return;
    }

    setState(() {
      resolviendo = true;
    });

    try {
      final dynamic respuesta = await supabase.rpc(
        'resolver_solicitud_cierre_excepcional',
        params: <String, dynamic>{
          'p_id_alerta': widget.idAlerta,
          'p_decision': aprobar ? 'Aprobar' : 'Rechazar',
          'p_comentario': comentario,
        },
      );

      if (respuesta is! Map) {
        throw Exception('Respuesta inválida al resolver la solicitud.');
      }

      final Map<String, dynamic> resultado = Map<String, dynamic>.from(
        respuesta,
      );

      if (resultado['ok'] != true) {
        throw Exception('No fue posible resolver la solicitud.');
      }

      if (!mounted) {
        return;
      }

      final String decision =
          resultado['decision']?.toString() ??
          (aprobar ? 'Aprobada' : 'Rechazada');

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            icon: Icon(
              aprobar ? Icons.check_circle : Icons.cancel,
              color: aprobar
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFDC2626),
              size: 46,
            ),
            title: Text(
              aprobar ? 'Cierre aprobado' : 'Solicitud rechazada',
              textAlign: TextAlign.center,
            ),
            content: Text(
              aprobar
                  ? 'La labor quedó registrada como "Incompleta - Cerrada por Supervisor".'
                  : 'La solicitud fue rechazada y la labor volvió a quedar disponible para continuar.',
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

      debugPrint('SOLICITUD ${widget.idAlerta} RESUELTA: $decision');

      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      debugPrint('ERROR RESOLVIENDO CIERRE EXCEPCIONAL: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        resolviendo = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible resolver la solicitud: $error'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  // =============================================================
  // COLORES
  // =============================================================

  Color get colorEstado {
    switch (estadoSolicitud) {
      case 'Leída':
      case 'En atención':
        return const Color(0xFF2563EB);

      default:
        return const Color(0xFFD97706);
    }
  }

  Color get fondoEstado {
    switch (estadoSolicitud) {
      case 'Leída':
      case 'En atención':
        return const Color(0xFFEFF6FF);

      default:
        return const Color(0xFFFFFBEB);
    }
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
        title: const Text(
          'Detalle de solicitud',
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
                  // ===============================================
                  // ESTADO
                  // ===============================================

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: fondoEstado,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      estadoSolicitud,
                      style: TextStyle(
                        color: colorEstado,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ===============================================
                  // INFORMACIÓN
                  // ===============================================
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
                          'Información de la solicitud',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),

                        const SizedBox(height: 20),

                        _DatoSolicitud(
                          titulo: 'Registro',
                          valor: '#${widget.idRegistroAseo}',
                          icono: Icons.tag_outlined,
                        ),

                        _DatoSolicitud(
                          titulo: 'Auxiliar',
                          valor: widget.responsable,
                          icono: Icons.person_outline,
                        ),

                        _DatoSolicitud(
                          titulo: 'Lugar',
                          valor: widget.lugar,
                          icono: Icons.location_on_outlined,
                        ),

                        _DatoSolicitud(
                          titulo: 'Inicio de la labor',
                          valor: widget.inicio,
                          icono: Icons.schedule_outlined,
                        ),

                        _DatoSolicitud(
                          titulo: 'Solicitud',
                          valor: '${widget.fecha} · ${widget.horaSolicitud}',
                          icono: Icons.calendar_today_outlined,
                          mostrarSeparador: false,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ===============================================
                  // MOTIVO
                  // ===============================================
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
                              Icons.report_problem_outlined,
                              color: Color(0xFFD97706),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Motivo del cierre excepcional',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        Text(
                          widget.motivo,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF78350F),
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          widget.detalle,
                          style: const TextStyle(
                            color: Color(0xFF78350F),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ===============================================
                  // EXPLICACIÓN
                  // ===============================================
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFF1565C0)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Si apruebas, la labor quedará cerrada excepcionalmente con trazabilidad del Supervisor. '
                            'Si rechazas, la labor volverá a quedar abierta para que el Auxiliar pueda continuar.',
                            style: TextStyle(
                              color: Color(0xFF1E40AF),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 26),

                  // ===============================================
                  // APROBAR
                  // ===============================================
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: resolviendo
                          ? null
                          : () {
                              resolver(aprobar: true);
                            },
                      icon: resolviendo
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
                        resolviendo
                            ? 'Procesando...'
                            : 'Aprobar cierre excepcional',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ===============================================
                  // RECHAZAR
                  // ===============================================
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: resolviendo
                          ? null
                          : () {
                              resolver(aprobar: false);
                            },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text(
                        'Rechazar solicitud',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFDC2626)),
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
// DATO
// =================================================================

class _DatoSolicitud extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icono;
  final bool mostrarSeparador;

  const _DatoSolicitud({
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
