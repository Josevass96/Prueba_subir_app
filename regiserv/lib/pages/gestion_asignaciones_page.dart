import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'nueva_asignacion_page.dart';

class GestionAsignacionesPage extends StatefulWidget {
  const GestionAsignacionesPage({super.key});

  @override
  State<GestionAsignacionesPage> createState() =>
      _GestionAsignacionesPageState();
}

class _GestionAsignacionesPageState extends State<GestionAsignacionesPage> {
  final buscarController = TextEditingController();

  SupabaseClient get supabase => Supabase.instance.client;

  List<Map<String, dynamic>> asignaciones = [];

  String textoBusqueda = '';
  String filtroEstado = 'Vigentes';

  bool cargando = true;

  String? mensajeError;

  String? asignacionProcesando;

  @override
  void initState() {
    super.initState();

    cargarAsignaciones();
  }

  @override
  void dispose() {
    buscarController.dispose();

    super.dispose();
  }

  // =============================================================
  // NOMBRE
  // =============================================================

  String nombreCompleto(Map<String, dynamic> usuario) {
    return [
          usuario['p_nombre'],
          usuario['s_nombre'],
          usuario['apellido_pater'],
          usuario['apellido_mater'],
        ]
        .map((v) => (v ?? '').toString().trim())
        .where((v) => v.isNotEmpty)
        .join(' ');
  }

  DateTime fechaLocal(dynamic valor) {
    return DateTime.parse(valor.toString()).toLocal();
  }

  // =============================================================
  // CARGAR ASIGNACIONES
  // =============================================================

  Future<void> cargarAsignaciones() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;
      });
    }

    try {
      // ---------------------------------------------------------
      // USUARIOS
      // ---------------------------------------------------------

      final usuariosData = await supabase
          .from('usuario')
          .select(
            'id_usuario, '
            'p_nombre, '
            's_nombre, '
            'apellido_pater, '
            'apellido_mater',
          );

      final Map<String, String> usuariosPorId = {};

      for (final fila in usuariosData) {
        final usuario = Map<String, dynamic>.from(fila);

        usuariosPorId[usuario['id_usuario'].toString()] = nombreCompleto(
          usuario,
        );
      }

      // ---------------------------------------------------------
      // EDIFICIOS
      // ---------------------------------------------------------

      final edificiosData = await supabase
          .from('edificio')
          .select(
            'id_edificio, '
            'nombre, '
            'codigo',
          );

      final Map<String, Map<String, dynamic>> edificiosPorId = {};

      for (final fila in edificiosData) {
        final edificio = Map<String, dynamic>.from(fila);

        edificiosPorId[edificio['id_edificio'].toString()] = edificio;
      }

      // ---------------------------------------------------------
      // PISOS
      // ---------------------------------------------------------

      final pisosData = await supabase
          .from('piso_nivel')
          .select(
            'id_piso, '
            'id_edificio, '
            'numero_nivel',
          );

      final Map<String, Map<String, dynamic>> pisosPorId = {};

      for (final fila in pisosData) {
        final piso = Map<String, dynamic>.from(fila);

        pisosPorId[piso['id_piso'].toString()] = piso;
      }

      // ---------------------------------------------------------
      // TIPOS
      // ---------------------------------------------------------

      final tiposData = await supabase
          .from('tipo_espacio')
          .select(
            'id_tipo_espacio, '
            'nombre',
          );

      final Map<String, String> tiposPorId = {};

      for (final fila in tiposData) {
        tiposPorId[fila['id_tipo_espacio'].toString()] = fila['nombre']
            .toString();
      }

      // ---------------------------------------------------------
      // ESPACIOS
      // ---------------------------------------------------------

      final espaciosData = await supabase
          .from('espacio')
          .select(
            'id_espacio, '
            'id_piso, '
            'id_tipo_espacio, '
            'codigo, '
            'nombre',
          );

      final Map<String, Map<String, dynamic>> espaciosPorId = {};

      for (final fila in espaciosData) {
        final espacio = Map<String, dynamic>.from(fila);

        espaciosPorId[espacio['id_espacio'].toString()] = {
          ...espacio,

          'tipo':
              tiposPorId[espacio['id_tipo_espacio'].toString()] ?? 'Sin tipo',
        };
      }

      // ---------------------------------------------------------
      // PISO_TRABAJADOR
      // ---------------------------------------------------------

      final pisosTrabajadorData = await supabase
          .from('piso_trabajador')
          .select(
            'id_usuario, '
            'id_piso, '
            'fecha_ini, '
            'fecha_fin, '
            'comentario',
          );

      // ---------------------------------------------------------
      // ESPACIO_TRABAJADOR
      // ---------------------------------------------------------

      final espaciosTrabajadorData = await supabase
          .from('espacio_trabajador')
          .select(
            'id_usuario, '
            'id_espacio, '
            'fecha_ini, '
            'fecha_ter, '
            'comentario',
          );

      final List<Map<String, dynamic>> resultado = [];

      for (final fila in pisosTrabajadorData) {
        final idUsuario = fila['id_usuario'].toString();

        final idPiso = fila['id_piso'].toString();

        final fechaInicioDb = fila['fecha_ini'].toString();

        final DateTime fechaInicioPiso = fechaLocal(fechaInicioDb);

        final DateTime? fechaFinPiso = fila['fecha_fin'] == null
            ? null
            : fechaLocal(fila['fecha_fin']);

        final piso = pisosPorId[idPiso];

        if (piso == null) {
          continue;
        }

        final edificio = edificiosPorId[piso['id_edificio'].toString()];

        final List<Map<String, dynamic>> espaciosAsignados = [];

        for (final filaEspacio in espaciosTrabajadorData) {
          if (filaEspacio['id_usuario'].toString() != idUsuario) {
            continue;
          }

          final espacio = espaciosPorId[filaEspacio['id_espacio'].toString()];

          if (espacio == null || espacio['id_piso'].toString() != idPiso) {
            continue;
          }

          final DateTime fechaInicioEspacio = fechaLocal(
            filaEspacio['fecha_ini'],
          );

          final DateTime? fechaTerminoEspacio = filaEspacio['fecha_ter'] == null
              ? null
              : fechaLocal(filaEspacio['fecha_ter']);

          // -------------------------------------------------------
          // ASIGNACIÓN VIGENTE
          //
          // Mostramos todos los espacios que actualmente están
          // vigentes para este Auxiliar en este piso, aunque hayan
          // sido agregados después de la fecha inicial del piso.
          // -------------------------------------------------------

          if (fechaFinPiso == null) {
            if (fechaTerminoEspacio != null) {
              continue;
            }
          } else {
            // -----------------------------------------------------
            // ASIGNACIÓN HISTÓRICA
            //
            // Mostramos los espacios cuyo período de asignación
            // se superpuso con el período de este piso.
            // -----------------------------------------------------

            if (fechaInicioEspacio.isAfter(fechaFinPiso)) {
              continue;
            }

            if (fechaTerminoEspacio != null &&
                fechaTerminoEspacio.isBefore(fechaInicioPiso)) {
              continue;
            }
          }

          espaciosAsignados.add({
            ...espacio,

            'fechaInicio': fechaInicioEspacio,

            'fechaTer': fechaTerminoEspacio,

            'comentario': filaEspacio['comentario'],
          });
        }

        espaciosAsignados.sort(
          (a, b) => a['codigo'].toString().compareTo(b['codigo'].toString()),
        );

        resultado.add({
          'idUsuario': idUsuario,

          'idPiso': int.parse(idPiso),

          'auxiliarNombre': usuariosPorId[idUsuario] ?? 'Usuario',

          'edificioNombre': edificio?['nombre']?.toString() ?? 'Edificio',

          'edificioCodigo': edificio?['codigo']?.toString() ?? '-',

          'pisoNumero': piso['numero_nivel'].toString(),

          'fechaInicio': fechaInicioPiso,

          // Se conserva la fecha original del piso únicamente
          // para identificar cuál fila de piso_trabajador cerrar.
          'fechaInicioDb': fechaInicioDb,

          'fechaFin': fechaFinPiso,

          'comentario': fila['comentario'],

          'espacios': espaciosAsignados,
        });
      }

      resultado.sort((a, b) {
        final vigenteA = a['fechaFin'] == null;

        final vigenteB = b['fechaFin'] == null;

        if (vigenteA != vigenteB) {
          return vigenteA ? -1 : 1;
        }

        final nombre = a['auxiliarNombre'].toString().compareTo(
          b['auxiliarNombre'].toString(),
        );

        if (nombre != 0) {
          return nombre;
        }

        final edificio = a['edificioCodigo'].toString().compareTo(
          b['edificioCodigo'].toString(),
        );

        if (edificio != 0) {
          return edificio;
        }

        return int.parse(a['pisoNumero'].toString())
            .compareTo(int.parse(b['pisoNumero'].toString()));
      });

      if (!mounted) {
        return;
      }

      setState(() {
        asignaciones = resultado;

        cargando = false;
      });
    } catch (error) {
      debugPrint('ERROR CARGANDO ASIGNACIONES: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;

        mensajeError = 'No fue posible cargar las asignaciones desde Supabase.';
      });
    }
  }

  // =============================================================
  // FILTROS
  // =============================================================

  List<Map<String, dynamic>> get asignacionesFiltradas {
    final resultado = asignaciones.where((asignacion) {
      final vigente = asignacion['fechaFin'] == null;

      final cumpleEstado =
          filtroEstado == 'Todas' ||
          (filtroEstado == 'Vigentes' && vigente) ||
          (filtroEstado == 'Finalizadas' && !vigente);

      final busqueda = textoBusqueda.trim().toLowerCase();

      final auxiliar = asignacion['auxiliarNombre'].toString().toLowerCase();

      final edificio = asignacion['edificioNombre'].toString().toLowerCase();

      final codigo = asignacion['edificioCodigo'].toString().toLowerCase();

      final piso = asignacion['pisoNumero'].toString().toLowerCase();

      final cumpleBusqueda =
          busqueda.isEmpty ||
          auxiliar.contains(busqueda) ||
          edificio.contains(busqueda) ||
          codigo.contains(busqueda) ||
          piso.contains(busqueda);

      return cumpleEstado && cumpleBusqueda;
    }).toList();

    return resultado;
  }

  // =============================================================
  // NUEVA ASIGNACIÓN
  // =============================================================

  Future<void> nuevaAsignacion() async {
    final creado = await Navigator.push<bool>(
      context,

      MaterialPageRoute(builder: (context) => const NuevaAsignacionPage()),
    );

    if (creado != true || !mounted) {
      return;
    }

    await cargarAsignaciones();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Asignación creada correctamente.'),

        backgroundColor: Color(0xFF16A34A),
      ),
    );
  }

  // =============================================================
  // FINALIZAR
  // =============================================================

  Future<void> quitarAsignacion(Map<String, dynamic> asignacion) async {
    if (asignacion['fechaFin'] != null) {
      return;
    }

    final comentarioController = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,

      builder: (context) {
        return AlertDialog(
          title: const Text('Quitar piso completo'),

          content: Column(
            mainAxisSize: MainAxisSize.min,

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Text(
                '¿Deseas quitar el Piso '
                '${asignacion['pisoNumero']} '
                'del ${asignacion['edificioNombre']} '
                'a ${asignacion['auxiliarNombre']}?',
              ),

              const SizedBox(height: 16),

              TextField(
                controller: comentarioController,

                maxLines: 3,

                decoration: const InputDecoration(
                  labelText: 'Motivo o comentario opcional',

                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },

              child: const Text('Cancelar'),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),

                foregroundColor: Colors.white,
              ),

              onPressed: () {
                Navigator.pop(context, true);
              },

              child: const Text('Quitar piso completo'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      comentarioController.dispose();

      return;
    }

    final comentario = comentarioController.text.trim();

    comentarioController.dispose();

    final clave =
        '${asignacion['idUsuario']}|'
        '${asignacion['idPiso']}|'
        '${asignacion['fechaInicioDb']}';

    setState(() {
      asignacionProcesando = clave;
    });

    try {
      await supabase.rpc(
        'finalizar_asignacion_piso',

        params: {
          'p_id_usuario': asignacion['idUsuario'],

          'p_id_piso': asignacion['idPiso'],

          // La fecha identifica la fila del piso.
          // La RPC cerrará todos los espacios vigentes
          // del Auxiliar pertenecientes a ese piso.
          'p_fecha_inicio': asignacion['fechaInicioDb'],

          'p_comentario': comentario,
        },
      );

      await cargarAsignaciones();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Piso y espacios vigentes finalizados correctamente.'),

          backgroundColor: Color(0xFF16A34A),
        ),
      );
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),

          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    } catch (error) {
      debugPrint('ERROR FINALIZANDO ASIGNACIÓN: $error');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible finalizar la asignación.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          asignacionProcesando = null;
        });
      }
    }
  }

  // =============================================================
  // VER ESPACIOS
  // =============================================================

  // =============================================================
  // QUITAR ESPACIOS INDIVIDUALES
  // =============================================================

  Future<bool> quitarEspaciosSeleccionados(
    Map<String, dynamic> asignacion,
    List<Map<String, dynamic>> espaciosSeleccionados,
  ) async {
    if (espaciosSeleccionados.isEmpty) {
      return false;
    }

    final comentarioController = TextEditingController();

    final String nombres = espaciosSeleccionados
        .map(
          (espacio) =>
              espacio['codigo']?.toString() ??
              espacio['nombre']?.toString() ??
              'Espacio',
        )
        .join(', ');

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            espaciosSeleccionados.length == 1
                ? 'Quitar espacio'
                : 'Quitar espacios',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                espaciosSeleccionados.length == 1
                    ? '¿Deseas quitar $nombres de la asignación de '
                          '${asignacion['auxiliarNombre']}?'
                    : '¿Deseas quitar estos ${espaciosSeleccionados.length} '
                          'espacios de la asignación de '
                          '${asignacion['auxiliarNombre']}?\n\n$nombres',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: comentarioController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo o comentario opcional',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: Text(
                espaciosSeleccionados.length == 1
                    ? 'Quitar espacio'
                    : 'Quitar espacios',
              ),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      comentarioController.dispose();
      return false;
    }

    final comentario = comentarioController.text.trim();
    comentarioController.dispose();

    final idsEspacios = espaciosSeleccionados
        .map((espacio) => int.parse(espacio['id_espacio'].toString()))
        .toList();

    try {
      final dynamic respuesta = await supabase.rpc(
        'finalizar_asignaciones_espacio',
        params: {
          'p_id_usuario': asignacion['idUsuario'],
          'p_id_piso': asignacion['idPiso'],
          'p_ids_espacios': idsEspacios,
          'p_comentario': comentario,
        },
      );

      if (respuesta is! Map) {
        throw Exception(
          'La respuesta de Supabase no tiene el formato esperado.',
        );
      }

      final resultado = Map<String, dynamic>.from(respuesta);

      if (resultado['ok'] != true) {
        throw Exception(
          'Supabase no confirmó la finalización de los espacios.',
        );
      }

      final int finalizados =
          int.tryParse(resultado['espacios_finalizados']?.toString() ?? '0') ??
          0;

      final bool pisoFinalizado = resultado['piso_finalizado'] == true;

      await cargarAsignaciones();

      if (!mounted) {
        return true;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pisoFinalizado
                ? '$finalizados '
                      '${finalizados == 1 ? 'espacio finalizado' : 'espacios finalizados'}. '
                      'Como el piso quedó sin espacios vigentes, '
                      'también se finalizó su asignación.'
                : '$finalizados '
                      '${finalizados == 1 ? 'espacio finalizado' : 'espacios finalizados'} '
                      'correctamente.',
          ),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );

      return true;
    } on PostgrestException catch (error) {
      if (!mounted) {
        return false;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );

      return false;
    } catch (error) {
      debugPrint('ERROR FINALIZANDO ESPACIOS DE ASIGNACIÓN: $error');

      if (!mounted) {
        return false;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible quitar los espacios seleccionados.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );

      return false;
    }
  }

  // =============================================================
  // VER / GESTIONAR ESPACIOS
  // =============================================================

  void verEspacios(Map<String, dynamic> asignacion) {
    final espacios = List<Map<String, dynamic>>.from(asignacion['espacios']);

    final bool pisoVigente = asignacion['fechaFin'] == null;

    final Set<int> seleccionados = <int>{};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final List<Map<String, dynamic>> espaciosElegidos = espacios
                .where(
                  (espacio) => seleccionados.contains(
                    int.parse(espacio['id_espacio'].toString()),
                  ),
                )
                .toList();

            return SafeArea(
              child: FractionallySizedBox(
                heightFactor: 0.82,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${asignacion['edificioNombre']} · '
                                  'Piso ${asignacion['pisoNumero']}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  asignacion['auxiliarNombre'],
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),

                    if (pisoVigente && espacios.isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Selecciona uno o varios espacios si deseas '
                          'quitarlos sin finalizar la asignación completa '
                          'del piso.',
                          style: TextStyle(
                            color: Color(0xFF1E40AF),
                            height: 1.35,
                          ),
                        ),
                      ),

                    const Divider(height: 1),

                    Expanded(
                      child: espacios.isEmpty
                          ? const Center(
                              child: Text(
                                'Esta asignación no tiene espacios asociados.',
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: espacios.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(),
                              itemBuilder: (context, index) {
                                final espacio = espacios[index];

                                final bool vigente =
                                    espacio['fechaTer'] == null;

                                final int idEspacio = int.parse(
                                  espacio['id_espacio'].toString(),
                                );

                                if (pisoVigente && vigente) {
                                  return CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: seleccionados.contains(idEspacio),
                                    onChanged: (valor) {
                                      setModalState(() {
                                        if (valor == true) {
                                          seleccionados.add(idEspacio);
                                        } else {
                                          seleccionados.remove(idEspacio);
                                        }
                                      });
                                    },
                                    secondary: const Icon(
                                      Icons.meeting_room_outlined,
                                      color: Color(0xFF16A34A),
                                    ),
                                    title: Text(espacio['nombre'].toString()),
                                    subtitle: Text(
                                      '${espacio['tipo']} · '
                                      '${espacio['codigo']}',
                                    ),
                                  );
                                }

                                return ListTile(
                                  leading: Icon(
                                    Icons.meeting_room_outlined,
                                    color: vigente
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFF9CA3AF),
                                  ),
                                  title: Text(espacio['nombre'].toString()),
                                  subtitle: Text(
                                    '${espacio['tipo']} · '
                                    '${espacio['codigo']}',
                                  ),
                                  trailing: Text(
                                    vigente ? 'Vigente' : 'Finalizado',
                                    style: TextStyle(
                                      color: vigente
                                          ? const Color(0xFF16A34A)
                                          : const Color(0xFF6B7280),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),

                    if (pisoVigente && espacios.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            top: BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                        ),
                        child: ElevatedButton.icon(
                          onPressed: seleccionados.isEmpty
                              ? null
                              : () async {
                                  final bool quitados =
                                      await quitarEspaciosSeleccionados(
                                        asignacion,
                                        espaciosElegidos,
                                      );

                                  if (quitados &&
                                      Navigator.of(sheetContext).canPop()) {
                                    Navigator.pop(sheetContext);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFD1D5DB),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            minimumSize: const Size.fromHeight(50),
                          ),
                          icon: const Icon(Icons.remove_circle_outline),
                          label: Text(
                            seleccionados.isEmpty
                                ? 'Selecciona espacios para quitar'
                                : 'Quitar ${seleccionados.length} '
                                      '${seleccionados.length == 1 ? 'espacio seleccionado' : 'espacios seleccionados'}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // =============================================================
  // FECHA
  // =============================================================

  String formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');

    final mes = fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final lista = asignacionesFiltradas;

    final vigentes = asignaciones.where((a) => a['fechaFin'] == null).length;

    final espaciosVigentes = asignaciones
        .where((a) => a['fechaFin'] == null)
        .expand<Map<String, dynamic>>(
          (a) => List<Map<String, dynamic>>.from(a['espacios']),
        )
        .where((e) => e['fechaTer'] == null)
        .length;

    final auxiliaresConAsignacion = asignaciones
        .where((a) => a['fechaFin'] == null)
        .map((a) => a['idUsuario'].toString())
        .toSet()
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,

        surfaceTintColor: Colors.white,

        title: const Text(
          'Gestión de asignaciones',

          style: TextStyle(
            fontWeight: FontWeight.bold,

            color: Color(0xFF1F2937),
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Actualizar',

            onPressed: cargando ? null : cargarAsignaciones,

            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: nuevaAsignacion,

        icon: const Icon(Icons.add),

        label: const Text('Nueva asignación'),
      ),

      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 850),

            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      const Text(
                        'Sectores asignados',

                        style: TextStyle(
                          fontSize: 24,

                          fontWeight: FontWeight.bold,

                          color: Color(0xFF1F2937),
                        ),
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        'Administra los pisos y espacios que corresponden a cada Auxiliar.',

                        style: TextStyle(color: Color(0xFF6B7280)),
                      ),

                      const SizedBox(height: 18),

                      Container(
                        width: double.infinity,

                        padding: const EdgeInsets.all(14),

                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),

                          borderRadius: BorderRadius.circular(12),
                        ),

                        child: Wrap(
                          spacing: 22,
                          runSpacing: 8,

                          children: [
                            _Resumen(
                              icono: Icons.layers_outlined,

                              texto: '$vigentes pisos asignados',
                            ),

                            _Resumen(
                              icono: Icons.meeting_room_outlined,

                              texto: '$espaciosVigentes espacios asignados',
                            ),

                            _Resumen(
                              icono: Icons.people_outline,

                              texto: '$auxiliaresConAsignacion auxiliares',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      TextField(
                        controller: buscarController,

                        onChanged: (valor) {
                          setState(() {
                            textoBusqueda = valor;
                          });
                        },

                        decoration: InputDecoration(
                          hintText: 'Buscar Auxiliar, edificio o piso...',

                          prefixIcon: const Icon(Icons.search),

                          filled: true,

                          fillColor: Colors.white,

                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Wrap(
                        spacing: 8,

                        children: [
                          for (final estado in [
                            'Vigentes',
                            'Finalizadas',
                            'Todas',
                          ])
                            ChoiceChip(
                              label: Text(estado),

                              selected: filtroEstado == estado,

                              onSelected: (_) {
                                setState(() {
                                  filtroEstado = estado;
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: cargando
                      ? const Center(child: CircularProgressIndicator())
                      : mensajeError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(30),

                            child: Column(
                              mainAxisSize: MainAxisSize.min,

                              children: [
                                Text(
                                  mensajeError!,

                                  textAlign: TextAlign.center,
                                ),

                                const SizedBox(height: 16),

                                ElevatedButton.icon(
                                  onPressed: cargarAsignaciones,

                                  icon: const Icon(Icons.refresh),

                                  label: const Text('Reintentar'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : lista.isEmpty
                      ? const _SinAsignaciones()
                      : RefreshIndicator(
                          onRefresh: cargarAsignaciones,

                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),

                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),

                            itemCount: lista.length,

                            itemBuilder: (context, index) {
                              final asignacion = lista[index];

                              final vigente = asignacion['fechaFin'] == null;

                              final espacios = List<Map<String, dynamic>>.from(
                                asignacion['espacios'],
                              );

                              final cantidadEspacios = vigente
                                  ? espacios
                                        .where((e) => e['fechaTer'] == null)
                                        .length
                                  : espacios.length;

                              final clave =
                                  '${asignacion['idUsuario']}|'
                                  '${asignacion['idPiso']}|'
                                  '${asignacion['fechaInicioDb']}';

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),

                                child: _TarjetaAsignacion(
                                  asignacion: asignacion,

                                  cantidadEspacios: cantidadEspacios,

                                  formatearFecha: formatearFecha,

                                  procesando: asignacionProcesando == clave,

                                  onVerEspacios: () {
                                    verEspacios(asignacion);
                                  },

                                  onQuitar: vigente
                                      ? () {
                                          quitarAsignacion(asignacion);
                                        }
                                      : null,
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =================================================================
// TARJETA
// =================================================================

class _TarjetaAsignacion extends StatelessWidget {
  final Map<String, dynamic> asignacion;

  final int cantidadEspacios;

  final String Function(DateTime) formatearFecha;

  final VoidCallback onVerEspacios;

  final VoidCallback? onQuitar;

  final bool procesando;

  const _TarjetaAsignacion({
    required this.asignacion,
    required this.cantidadEspacios,
    required this.formatearFecha,
    required this.onVerEspacios,
    required this.onQuitar,
    required this.procesando,
  });

  @override
  Widget build(BuildContext context) {
    final vigente = asignacion['fechaFin'] == null;

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Container(
            width: 50,
            height: 50,

            decoration: BoxDecoration(
              color: vigente
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFF3F4F6),

              borderRadius: BorderRadius.circular(12),
            ),

            child: Icon(
              Icons.assignment_ind_outlined,

              color: vigente
                  ? const Color(0xFF16A34A)
                  : const Color(0xFF6B7280),
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  asignacion['auxiliarNombre'],

                  style: const TextStyle(
                    fontSize: 17,

                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  '${asignacion['edificioNombre']} · '
                  'Piso ${asignacion['pisoNumero']}',

                  style: const TextStyle(
                    color: Color(0xFF4B5563),

                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  '$cantidadEspacios '
                  '${cantidadEspacios == 1 ? 'espacio asignado' : 'espacios asignados'}',

                  style: const TextStyle(
                    fontSize: 13,

                    color: Color(0xFF6B7280),
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  'Desde '
                  '${formatearFecha(asignacion['fechaInicio'])}',

                  style: const TextStyle(
                    fontSize: 12,

                    color: Color(0xFF6B7280),
                  ),
                ),

                const SizedBox(height: 10),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),

                  decoration: BoxDecoration(
                    color: vigente
                        ? const Color(0xFFF0FDF4)
                        : const Color(0xFFF3F4F6),

                    borderRadius: BorderRadius.circular(20),
                  ),

                  child: Text(
                    vigente ? 'Vigente' : 'Finalizada',

                    style: TextStyle(
                      fontSize: 11,

                      fontWeight: FontWeight.w600,

                      color: vigente
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (procesando)
            const Padding(
              padding: EdgeInsets.all(10),

              child: SizedBox(
                width: 20,
                height: 20,

                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            PopupMenuButton<String>(
              onSelected: (valor) {
                if (valor == 'espacios') {
                  onVerEspacios();
                }

                if (valor == 'quitar' && onQuitar != null) {
                  onQuitar!();
                }
              },

              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'espacios',

                  child: Row(
                    children: [
                      Icon(Icons.meeting_room_outlined),

                      SizedBox(width: 10),

                      Text('Ver espacios'),
                    ],
                  ),
                ),

                if (vigente)
                  const PopupMenuItem(
                    value: 'quitar',

                    child: Row(
                      children: [
                        Icon(
                          Icons.remove_circle_outline,

                          color: Color(0xFFDC2626),
                        ),

                        SizedBox(width: 10),

                        Text('Quitar piso completo'),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// =================================================================
// RESUMEN
// =================================================================

class _Resumen extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _Resumen({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,

      children: [
        Icon(icono, size: 18, color: const Color(0xFF1565C0)),

        const SizedBox(width: 6),

        Text(
          texto,

          style: const TextStyle(
            color: Color(0xFF1E40AF),

            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// =================================================================
// VACÍO
// =================================================================

class _SinAsignaciones extends StatelessWidget {
  const _SinAsignaciones();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Icon(
              Icons.assignment_ind_outlined,

              size: 58,

              color: Color(0xFF9CA3AF),
            ),

            SizedBox(height: 14),

            Text(
              'No existen asignaciones',

              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            SizedBox(height: 6),

            Text(
              'Utiliza Nueva asignación para asignar pisos y espacios a un Auxiliar.',

              textAlign: TextAlign.center,

              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
