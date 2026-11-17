import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MarcarNfcDanadoPage extends StatefulWidget {
  const MarcarNfcDanadoPage({super.key});

  @override
  State<MarcarNfcDanadoPage> createState() => _MarcarNfcDanadoPageState();
}

class _MarcarNfcDanadoPageState extends State<MarcarNfcDanadoPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  final TextEditingController comentarioController = TextEditingController();

  bool cargando = true;
  bool enviando = false;

  String? errorCarga;

  int? idNfcSeleccionado;

  final List<Map<String, dynamic>> nfcDisponibles = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();

    cargarNfc();
  }

  @override
  void dispose() {
    comentarioController.dispose();

    super.dispose();
  }

  // =============================================================
  // CONVERSIÓN
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

  // =============================================================
  // CARGAR NFC OPERATIVOS REALES
  // =============================================================

  Future<void> cargarNfc() async {
    if (!mounted) {
      return;
    }

    setState(() {
      cargando = true;
      errorCarga = null;
      idNfcSeleccionado = null;
    });

    try {
      // ---------------------------------------------------------
      // BUSCAR ID DEL ESTADO OPERATIVO
      // ---------------------------------------------------------

      final dynamic estadoRaw = await supabase
          .from('estado_nfc')
          .select('id_estado_nfc')
          .eq('nombre_estado', 'Operativo')
          .single();

      if (estadoRaw is! Map) {
        throw Exception('No existe el estado NFC Operativo.');
      }

      final int? idEstadoOperativo = aInt(estadoRaw['id_estado_nfc']);

      if (idEstadoOperativo == null) {
        throw Exception('Estado NFC inválido.');
      }

      // ---------------------------------------------------------
      // NFC VIGENTES Y OPERATIVOS
      // ---------------------------------------------------------

      final List<dynamic> nfcRaw = await supabase
          .from('nfc')
          .select(
            'id_nfc, '
            'id_espacio, '
            'uid_nfc, '
            'fecha_instalacion',
          )
          .eq('id_estado_nfc', idEstadoOperativo)
          .isFilter('fecha_retiro', null)
          .order('id_nfc');

      final Set<int> idsEspacios = <int>{};

      final List<Map<String, dynamic>> nfcTemp = <Map<String, dynamic>>[];

      for (final dynamic fila in nfcRaw) {
        if (fila is! Map) {
          continue;
        }

        final Map<String, dynamic> item = Map<String, dynamic>.from(fila);

        final int? idEspacio = aInt(item['id_espacio']);

        if (idEspacio != null) {
          idsEspacios.add(idEspacio);
        }

        nfcTemp.add(item);
      }

      // ---------------------------------------------------------
      // DATOS DE LOS ESPACIOS
      // ---------------------------------------------------------

      final Map<int, Map<String, dynamic>> espaciosPorId = {};

      if (idsEspacios.isNotEmpty) {
        final List<dynamic> espaciosRaw = await supabase
            .from('espacio')
            .select(
              'id_espacio, '
              'codigo, '
              'nombre',
            )
            .inFilter('id_espacio', idsEspacios.toList());

        for (final dynamic fila in espaciosRaw) {
          if (fila is! Map) {
            continue;
          }

          final Map<String, dynamic> espacio = Map<String, dynamic>.from(fila);

          final int? id = aInt(espacio['id_espacio']);

          if (id != null) {
            espaciosPorId[id] = espacio;
          }
        }
      }

      final List<Map<String, dynamic>> resultado = <Map<String, dynamic>>[];

      for (final Map<String, dynamic> nfc in nfcTemp) {
        final int? idEspacio = aInt(nfc['id_espacio']);

        final Map<String, dynamic>? espacio = idEspacio == null
            ? null
            : espaciosPorId[idEspacio];

        resultado.add({
          ...nfc,
          'codigo_espacio': espacio?['codigo'] ?? 'Sin código',
          'nombre_espacio': espacio?['nombre'] ?? 'Espacio',
        });
      }

      if (!mounted) {
        return;
      }

      setState(() {
        nfcDisponibles
          ..clear()
          ..addAll(resultado);

        cargando = false;
        errorCarga = null;
      });
    } catch (e, stackTrace) {
      debugPrint('ERROR cargarNfc: $e');

      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;

        errorCarga = 'No fue posible cargar los NFC disponibles.';
      });
    }
  }

  // =============================================================
  // NFC SELECCIONADO
  // =============================================================

  Map<String, dynamic>? get nfcSeleccionado {
    if (idNfcSeleccionado == null) {
      return null;
    }

    for (final Map<String, dynamic> item in nfcDisponibles) {
      if (aInt(item['id_nfc']) == idNfcSeleccionado) {
        return item;
      }
    }

    return null;
  }

  bool get formularioValido {
    if (idNfcSeleccionado == null) {
      return false;
    }

    if (comentarioController.text.trim().isEmpty) {
      return false;
    }

    return true;
  }

  // =============================================================
  // MARCAR NFC DAÑADO REAL
  // =============================================================

  Future<void> marcarDanado() async {
    if (!formularioValido || enviando) {
      return;
    }

    final Map<String, dynamic>? seleccionado = nfcSeleccionado;

    final String codigo = (seleccionado?['codigo_espacio'] ?? '').toString();

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('¿Marcar NFC como dañado?'),
          content: Text(
            'El NFC asociado al espacio $codigo quedará inhabilitado '
            'para iniciar o finalizar labores hasta que sea reemplazado.',
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
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmar'),
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
        'marcar_nfc_danado',
        params: {
          'p_id_nfc': idNfcSeleccionado,
          'p_comentario': comentarioController.text.trim(),
        },
      );

      if (respuesta is! Map) {
        throw Exception('Respuesta inválida del servidor.');
      }

      final Map<String, dynamic> resultado = Map<String, dynamic>.from(
        respuesta,
      );

      if (resultado['ok'] != true) {
        throw Exception('No fue posible marcar el NFC como dañado.');
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
            title: const Text(
              'NFC marcado como dañado',
              textAlign: TextAlign.center,
            ),
            content: Text(
              'El NFC del espacio $codigo quedó inhabilitado '
              'y se generó una alerta en RegiServ.',
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

      // Volvemos al Home del Supervisor Jefe.
      // La pantalla que nos abrió ejecutará cargarResumen()
      // al recibir el pop.
      Navigator.pop(context, true);
    } catch (e, stackTrace) {
      debugPrint('ERROR marcarNfcDanado: $e');

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
            content: Text('No fue posible marcar el NFC como dañado: $e'),
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
          'Marcar NFC dañado',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
      ),

      body: SafeArea(
        child: cargando
            ? const Center(child: CircularProgressIndicator())
            : errorCarga != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Color(0xFFDC2626),
                      ),
                      const SizedBox(height: 12),
                      Text(errorCarga!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: cargarNfc,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
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
                            color: const Color(0xFFF5F3FF),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.nfc_outlined,
                                color: Color(0xFF7C3AED),
                                size: 30,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Al marcar un NFC como dañado dejará de estar '
                                  'disponible para validar labores en ese espacio.',
                                  style: TextStyle(
                                    color: Color(0xFF5B21B6),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 26),

                        const Text(
                          'Seleccionar NFC',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),

                        const SizedBox(height: 6),

                        Text(
                          nfcDisponibles.isEmpty
                              ? 'No existen NFC operativos actualmente.'
                              : 'Selecciona el espacio cuyo NFC presenta problemas.',
                          style: const TextStyle(color: Color(0xFF6B7280)),
                        ),

                        const SizedBox(height: 16),

                        if (nfcDisponibles.isNotEmpty)
                          DropdownButtonFormField<int>(
                            value: idNfcSeleccionado,
                            decoration: InputDecoration(
                              labelText: 'NFC / Espacio *',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            isExpanded: true,
                            items: nfcDisponibles.map((item) {
                              final int idNfc = aInt(item['id_nfc']) ?? 0;

                              final String codigo =
                                  (item['codigo_espacio'] ?? '').toString();

                              final String nombre =
                                  (item['nombre_espacio'] ?? '').toString();

                              return DropdownMenuItem<int>(
                                value: idNfc,
                                child: Text(
                                  '$codigo · $nombre',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: enviando
                                ? null
                                : (valor) {
                                    setState(() {
                                      idNfcSeleccionado = valor;
                                    });
                                  },
                          ),

                        if (nfcSeleccionado != null) ...[
                          const SizedBox(height: 16),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'NFC seleccionado',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),

                                const SizedBox(height: 12),

                                Text(
                                  'Espacio: '
                                  '${nfcSeleccionado!['codigo_espacio']} '
                                  '- ${nfcSeleccionado!['nombre_espacio']}',
                                ),

                                const SizedBox(height: 6),

                                Text(
                                  'UID: '
                                  '${nfcSeleccionado!['uid_nfc']}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        TextField(
                          controller: comentarioController,
                          enabled: !enviando && nfcDisponibles.isNotEmpty,
                          maxLines: 4,
                          onChanged: (_) {
                            setState(() {});
                          },
                          decoration: InputDecoration(
                            labelText: 'Problema detectado *',
                            hintText: 'Ej.: La etiqueta no responde al acercar el teléfono.',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: formularioValido && !enviando
                                ? marcarDanado
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7C3AED),
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
                                : const Icon(Icons.report_problem_outlined),
                            label: Text(
                              enviando
                                  ? 'Actualizando...'
                                  : 'Marcar NFC como dañado',
                              style: const TextStyle(
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
    );
  }
}
