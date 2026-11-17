import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auxiliar_home_page.dart';

class SolicitarCierreExcepcionalPage extends StatefulWidget {
  final String nombreAuxiliar;
  final String lugar;
  final DateTime horaInicio;

  const SolicitarCierreExcepcionalPage({
    super.key,
    required this.nombreAuxiliar,
    required this.lugar,
    required this.horaInicio,
  });

  @override
  State<SolicitarCierreExcepcionalPage> createState() =>
      _SolicitarCierreExcepcionalPageState();
}

class _SolicitarCierreExcepcionalPageState
    extends State<SolicitarCierreExcepcionalPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  final TextEditingController detalleController = TextEditingController();

  String? motivoSeleccionado;

  bool enviando = false;

  final List<String> motivos = const [
    'NFC dañado o no disponible',
    'Problema de ubicación GPS',
    'Falla técnica del dispositivo',
    'Imposibilidad de acceder al espacio',
    'Otro',
  ];

  @override
  void dispose() {
    detalleController.dispose();
    super.dispose();
  }

  // =============================================================
  // FORMATO
  // =============================================================

  String formatearHora(DateTime fecha) {
    final String hora = fecha.hour.toString().padLeft(2, '0');

    final String minuto = fecha.minute.toString().padLeft(2, '0');

    return '$hora:$minuto';
  }

  // =============================================================
  // VALIDACIÓN
  // =============================================================

  bool get formularioValido {
    if (motivoSeleccionado == null) {
      return false;
    }

    if (detalleController.text.trim().isEmpty) {
      return false;
    }

    return true;
  }

  // =============================================================
  // ENVIAR SOLICITUD REAL
  // =============================================================

  Future<void> enviarSolicitud() async {
    if (!formularioValido || enviando) {
      return;
    }

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('¿Solicitar cierre excepcional?'),
          content: const Text(
            'La labor será cerrada excepcionalmente y se enviará '
            'una solicitud pendiente de revisión al Supervisor Jefe.',
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
              child: const Text('Enviar solicitud'),
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
      enviando = true;
    });

    try {
      final dynamic respuesta = await supabase.rpc(
        'solicitar_cierre_excepcional',
        params: {
          'p_motivo': motivoSeleccionado,
          'p_detalle': detalleController.text.trim(),
        },
      );

      if (respuesta is! Map) {
        throw Exception('Respuesta inválida del servidor.');
      }

      final Map<String, dynamic> resultado = Map<String, dynamic>.from(
        respuesta,
      );

      if (resultado['ok'] != true) {
        throw Exception('No fue posible registrar la solicitud.');
      }

      if (!mounted) {
        return;
      }

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
            title: const Text('Solicitud enviada', textAlign: TextAlign.center),
            content: const Text(
              'La labor fue cerrada excepcionalmente y la solicitud '
              'quedó pendiente de revisión por el Supervisor Jefe.',
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

      // Al cerrarse la labor ya no corresponde
      // volver a Labor en curso.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AuxiliarHomePage()),
        (route) => false,
      );
    } catch (e, stackTrace) {
      debugPrint('ERROR enviarSolicitudCierre: $e');

      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        enviando = false;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('No fue posible enviar la solicitud: $e'),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Cierre excepcional',
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
                  // ADVERTENCIA
                  // =================================================

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFD97706),
                          size: 28,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Utiliza esta opción únicamente cuando no sea '
                            'posible finalizar la labor mediante la validación '
                            'normal de NFC y ubicación.',
                            style: TextStyle(
                              color: Color(0xFF92400E),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

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
                          'Labor en curso',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),

                        const SizedBox(height: 18),

                        _DatoCierre(
                          titulo: 'Auxiliar',
                          valor: widget.nombreAuxiliar,
                          icono: Icons.person_outline,
                        ),

                        const SizedBox(height: 14),

                        _DatoCierre(
                          titulo: 'Lugar',
                          valor: widget.lugar,
                          icono: Icons.location_on_outlined,
                        ),

                        const SizedBox(height: 14),

                        _DatoCierre(
                          titulo: 'Hora de inicio',
                          valor: formatearHora(widget.horaInicio),
                          icono: Icons.schedule,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 26),

                  // =================================================
                  // MOTIVO
                  // =================================================
                  const Text(
                    'Motivo del cierre',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    'Selecciona la razón que impide completar el cierre normal.',
                    style: TextStyle(color: Color(0xFF6B7280)),
                  ),

                  const SizedBox(height: 14),

                  DropdownButtonFormField<String>(
                    value: motivoSeleccionado,
                    decoration: InputDecoration(
                      labelText: 'Motivo *',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: motivos.map((motivo) {
                      return DropdownMenuItem<String>(
                        value: motivo,
                        child: Text(motivo),
                      );
                    }).toList(),
                    onChanged: enviando
                        ? null
                        : (valor) {
                            setState(() {
                              motivoSeleccionado = valor;
                            });
                          },
                  ),

                  const SizedBox(height: 16),

                  TextField(
                    controller: detalleController,
                    enabled: !enviando,
                    maxLines: 5,
                    onChanged: (_) {
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      labelText: 'Detalle *',
                      hintText: 'Describe brevemente lo ocurrido.',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: formularioValido && !enviando
                          ? enviarSolicitud
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: enviando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.support_agent_outlined),
                      label: Text(
                        enviando
                            ? 'Enviando...'
                            : 'Solicitar cierre excepcional',
                        style: const TextStyle(fontWeight: FontWeight.w600),
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

class _DatoCierre extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icono;

  const _DatoCierre({
    required this.titulo,
    required this.valor,
    required this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, color: const Color(0xFF1565C0), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
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
    );
  }
}
