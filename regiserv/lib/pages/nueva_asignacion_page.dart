import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NuevaAsignacionPage extends StatefulWidget {
  const NuevaAsignacionPage({super.key});

  @override
  State<NuevaAsignacionPage> createState() => _NuevaAsignacionPageState();
}

class _NuevaAsignacionPageState extends State<NuevaAsignacionPage> {
  final comentarioController = TextEditingController();

  SupabaseClient get supabase => Supabase.instance.client;

  // =============================================================
  // DATOS REALES
  // =============================================================

  List<Map<String, dynamic>> usuarios = [];
  List<Map<String, dynamic>> auxiliares = [];
  List<Map<String, dynamic>> edificios = [];
  List<Map<String, dynamic>> pisos = [];
  List<Map<String, dynamic>> espacios = [];
  List<Map<String, dynamic>> tipos = [];

  final Map<String, String> nombreUsuarioPorId = {};

  final Map<String, String> ocupantePorEspacio = {};

  // Usuario que mantiene actualmente cada espacio.
  final Map<String, String> usuarioPorEspacio = {};

  final Set<String> espaciosOcupados = {};

  String? auxiliarId;
  int? edificioId;

  final Set<int> pisosSeleccionados = {};

  final Set<int> espaciosSeleccionados = {};

  DateTime fechaInicio = DateTime.now();

  bool cargando = true;
  bool guardando = false;

  String? mensajeError;

  // =============================================================
  // INICIALIZACIÓN
  // =============================================================

  @override
  void initState() {
    super.initState();

    cargarDatos();
  }

  @override
  void dispose() {
    comentarioController.dispose();

    super.dispose();
  }

  // =============================================================
  // NOMBRE COMPLETO
  // =============================================================

  String nombreCompleto(Map<String, dynamic> usuario) {
    return [
          usuario['p_nombre'],
          usuario['s_nombre'],
          usuario['apellido_pater'],
          usuario['apellido_mater'],
        ]
        .map((valor) => (valor ?? '').toString().trim())
        .where((valor) => valor.isNotEmpty)
        .join(' ');
  }

  // =============================================================
  // CARGAR TODO DESDE SUPABASE
  // =============================================================

  Future<void> cargarDatos() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;
      });
    }

    try {
      // ---------------------------------------------------------
      // ROL AUXILIAR
      // ---------------------------------------------------------

      final rolAuxiliar = await supabase
          .from('rol')
          .select('id_rol, nombre')
          .eq('nombre', 'Auxiliar')
          .single();

      final idRolAuxiliar = rolAuxiliar['id_rol'];

      // ---------------------------------------------------------
      // USUARIOS
      // ---------------------------------------------------------

      final usuariosData = await supabase
          .from('usuario')
          .select(
            'id_usuario, '
            'id_rol, '
            'p_nombre, '
            's_nombre, '
            'apellido_pater, '
            'apellido_mater, '
            'activo',
          );

      final usuariosLista = usuariosData
          .map<Map<String, dynamic>>((fila) => Map<String, dynamic>.from(fila))
          .toList();

      final auxiliaresLista = usuariosLista
          .where(
            (usuario) =>
                usuario['activo'] == true &&
                usuario['id_rol'].toString() == idRolAuxiliar.toString(),
          )
          .toList();

      auxiliaresLista.sort(
        (a, b) =>
            nombreCompleto(a)
                .toLowerCase()
                .compareTo(nombreCompleto(b).toLowerCase()),
      );

      // ---------------------------------------------------------
      // EDIFICIOS
      // ---------------------------------------------------------

      final edificiosData = await supabase
          .from('edificio')
          .select(
            'id_edificio, '
            'codigo, '
            'nombre, '
            'activo',
          );

      final edificiosLista = edificiosData
          .map<Map<String, dynamic>>((fila) => Map<String, dynamic>.from(fila))
          .where((edificio) => edificio['activo'] == true)
          .toList();

      edificiosLista.sort(
        (a, b) => a['nombre'].toString().compareTo(b['nombre'].toString()),
      );

      // ---------------------------------------------------------
      // PISOS
      // ---------------------------------------------------------

      final pisosData = await supabase
          .from('piso_nivel')
          .select(
            'id_piso, '
            'id_edificio, '
            'numero_nivel, '
            'activo',
          );

      final pisosLista = pisosData
          .map<Map<String, dynamic>>((fila) => Map<String, dynamic>.from(fila))
          .where((piso) => piso['activo'] == true)
          .toList();

      // ---------------------------------------------------------
      // TIPOS
      // ---------------------------------------------------------

      final tiposData = await supabase
          .from('tipo_espacio')
          .select(
            'id_tipo_espacio, '
            'nombre',
          );

      final tiposLista = tiposData
          .map<Map<String, dynamic>>((fila) => Map<String, dynamic>.from(fila))
          .toList();

      final Map<String, String> tipoPorId = {};

      for (final tipo in tiposLista) {
        tipoPorId[tipo['id_tipo_espacio'].toString()] = tipo['nombre']
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
            'nombre, '
            'activo',
          );

      final espaciosLista = espaciosData
          .map<Map<String, dynamic>>((fila) {
            final espacio = Map<String, dynamic>.from(fila);

            return {
              ...espacio,

              'tipo':
                  tipoPorId[espacio['id_tipo_espacio'].toString()] ??
                  'Sin tipo',

              'nombreVisible': (espacio['nombre'] ?? espacio['codigo'])
                  .toString(),
            };
          })
          .where((espacio) => espacio['activo'] == true)
          .toList();

      // ---------------------------------------------------------
      // ASIGNACIONES DE ESPACIOS
      // ---------------------------------------------------------

      final asignacionesData = await supabase
          .from('espacio_trabajador')
          .select(
            'id_usuario, '
            'id_espacio, '
            'fecha_ini, '
            'fecha_ter',
          );

      final Map<String, String> nombres = {};

      for (final usuario in usuariosLista) {
        nombres[usuario['id_usuario'].toString()] = nombreCompleto(usuario);
      }

      final Set<String> ocupados = {};

      final Map<String, String> ocupantes = {};

      final Map<String, String> usuariosOcupantes = {};

      for (final asignacion in asignacionesData) {
        if (asignacion['fecha_ter'] != null) {
          continue;
        }

        final idEspacio = asignacion['id_espacio'].toString();

        final idUsuario = asignacion['id_usuario'].toString();

        ocupados.add(idEspacio);

        ocupantes[idEspacio] = nombres[idUsuario] ?? 'Otro Auxiliar';

        usuariosOcupantes[idEspacio] = idUsuario;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        usuarios = usuariosLista;

        auxiliares = auxiliaresLista;

        edificios = edificiosLista;

        pisos = pisosLista;

        espacios = espaciosLista;

        tipos = tiposLista;

        nombreUsuarioPorId
          ..clear()
          ..addAll(nombres);

        espaciosOcupados
          ..clear()
          ..addAll(ocupados);

        ocupantePorEspacio
          ..clear()
          ..addAll(ocupantes);

        usuarioPorEspacio
          ..clear()
          ..addAll(usuariosOcupantes);

        cargando = false;
      });
    } catch (error) {
      debugPrint('ERROR CARGANDO NUEVA ASIGNACIÓN: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;

        mensajeError =
            'No fue posible cargar los datos para crear la asignación.';
      });
    }
  }

  // =============================================================
  // PISOS DEL EDIFICIO
  // =============================================================

  List<Map<String, dynamic>> get pisosDelEdificio {
    if (edificioId == null) {
      return [];
    }

    final resultado = pisos
        .where(
          (piso) => piso['id_edificio'].toString() == edificioId.toString(),
        )
        .toList();

    resultado.sort((a, b) {
      final aNumero = int.tryParse(a['numero_nivel'].toString()) ?? 0;

      final bNumero = int.tryParse(b['numero_nivel'].toString()) ?? 0;

      return aNumero.compareTo(bNumero);
    });

    return resultado;
  }

  // =============================================================
  // ESPACIOS DE UN PISO
  // =============================================================

  List<Map<String, dynamic>> espaciosDelPiso(int idPiso) {
    final resultado = espacios
        .where((espacio) => espacio['id_piso'].toString() == idPiso.toString())
        .toList();

    resultado.sort(
      (a, b) => a['codigo'].toString().compareTo(b['codigo'].toString()),
    );

    return resultado;
  }

  // =============================================================
  // DISPONIBILIDAD
  // =============================================================

  String? usuarioAsignadoAlEspacio(Map<String, dynamic> espacio) {
    return usuarioPorEspacio[espacio['id_espacio'].toString()];
  }

  bool espacioAsignadoAlAuxiliar(Map<String, dynamic> espacio) {
    if (auxiliarId == null) {
      return false;
    }

    return usuarioAsignadoAlEspacio(espacio) == auxiliarId;
  }

  bool espacioOcupadoPorOtro(Map<String, dynamic> espacio) {
    final String? usuarioAsignado = usuarioAsignadoAlEspacio(espacio);

    if (usuarioAsignado == null) {
      return false;
    }

    return usuarioAsignado != auxiliarId;
  }

  bool espacioDisponible(Map<String, dynamic> espacio) {
    return usuarioAsignadoAlEspacio(espacio) == null;
  }

  // =============================================================
  // SELECCIONAR EDIFICIO
  // =============================================================

  void seleccionarEdificio(int? id) {
    setState(() {
      edificioId = id;

      pisosSeleccionados.clear();
      espaciosSeleccionados.clear();
    });
  }

  // =============================================================
  // SELECCIONAR PISO
  // =============================================================

  void cambiarSeleccionPiso(int idPiso, bool seleccionado) {
    final espaciosPiso = espaciosDelPiso(idPiso);

    setState(() {
      if (seleccionado) {
        pisosSeleccionados.add(idPiso);

        for (final espacio in espaciosPiso) {
          if (espacioDisponible(espacio)) {
            espaciosSeleccionados.add(
              int.parse(espacio['id_espacio'].toString()),
            );
          }
        }
      } else {
        pisosSeleccionados.remove(idPiso);

        for (final espacio in espaciosPiso) {
          espaciosSeleccionados.remove(
            int.parse(espacio['id_espacio'].toString()),
          );
        }
      }
    });
  }

  // =============================================================
  // SELECCIONAR ESPACIO
  // =============================================================

  void cambiarSeleccionEspacio(int idEspacio, bool seleccionado) {
    setState(() {
      if (seleccionado) {
        espaciosSeleccionados.add(idEspacio);
      } else {
        espaciosSeleccionados.remove(idEspacio);
      }
    });
  }

  // =============================================================
  // TODOS LOS DISPONIBLES
  // =============================================================

  void seleccionarTodosPiso(int idPiso) {
    setState(() {
      for (final espacio in espaciosDelPiso(idPiso)) {
        if (espacioDisponible(espacio)) {
          espaciosSeleccionados.add(
            int.parse(espacio['id_espacio'].toString()),
          );
        }
      }
    });
  }

  void quitarTodosPiso(int idPiso) {
    setState(() {
      for (final espacio in espaciosDelPiso(idPiso)) {
        espaciosSeleccionados.remove(
          int.parse(espacio['id_espacio'].toString()),
        );
      }
    });
  }

  // =============================================================
  // FECHA
  // =============================================================

  Future<void> seleccionarFecha() async {
    final fecha = await showDatePicker(
      context: context,

      initialDate: fechaInicio,

      firstDate: DateTime(2020),

      lastDate: DateTime(2100),
    );

    if (fecha == null || !mounted) {
      return;
    }

    final ahora = DateTime.now();

    setState(() {
      fechaInicio = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        ahora.hour,
        ahora.minute,
        ahora.second,
        ahora.millisecond,
      );
    });
  }

  String formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');

    final mes = fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  // =============================================================
  // MENSAJE
  // =============================================================

  void mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // =============================================================
  // GUARDAR
  // =============================================================

  Future<void> guardar() async {
    if (guardando) {
      return;
    }

    if (auxiliarId == null) {
      mostrarMensaje('Selecciona un Auxiliar.');

      return;
    }

    if (edificioId == null) {
      mostrarMensaje('Selecciona un edificio.');

      return;
    }

    if (pisosSeleccionados.isEmpty) {
      mostrarMensaje('Selecciona al menos un piso.');

      return;
    }

    // Cada piso debe contener
    // al menos un espacio seleccionado.
    for (final idPiso in pisosSeleccionados) {
      final seleccionados = espaciosDelPiso(idPiso).where(
        (espacio) => espaciosSeleccionados.contains(
          int.parse(espacio['id_espacio'].toString()),
        ),
      );

      if (seleccionados.isEmpty) {
        final piso = pisos.firstWhere(
          (item) => item['id_piso'].toString() == idPiso.toString(),
        );

        mostrarMensaje(
          'El Piso ${piso['numero_nivel']} no tiene espacios seleccionados.',
        );

        return;
      }
    }

    // ---------------------------------------------------------
    // VALIDACIÓN LOCAL DE CONFLICTOS
    // ---------------------------------------------------------

    for (final idEspacio in espaciosSeleccionados) {
      final String? usuarioAsignado = usuarioPorEspacio[idEspacio.toString()];

      if (usuarioAsignado != null && usuarioAsignado != auxiliarId) {
        final espacio = espacios.firstWhere(
          (item) => item['id_espacio'].toString() == idEspacio.toString(),
        );

        mostrarMensaje(
          'El espacio ${espacio['codigo']} ya está asignado a '
          '${ocupantePorEspacio[idEspacio.toString()] ?? 'otro Auxiliar'}.',
        );

        return;
      }
    }

    final auxiliar = auxiliares.firstWhere(
      (item) => item['id_usuario'].toString() == auxiliarId,
    );

    final nombreAuxiliar = nombreCompleto(auxiliar);

    final confirmar = await showDialog<bool>(
      context: context,

      builder: (context) {
        return AlertDialog(
          title: const Text('Guardar asignación'),

          content: Text(
            'Se guardará la asignación de '
            '${pisosSeleccionados.length} '
            '${pisosSeleccionados.length == 1 ? 'piso' : 'pisos'} '
            'y ${espaciosSeleccionados.length} '
            '${espaciosSeleccionados.length == 1 ? 'espacio nuevo' : 'espacios nuevos'} '
            'para $nombreAuxiliar. '
            'Si un piso ya está vigente para este Auxiliar, se reutilizará. '
            '¿Deseas continuar?',
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

    final asignaciones = <Map<String, dynamic>>[];

    final pisosOrdenados = pisosSeleccionados.toList()..sort();

    for (final idPiso in pisosOrdenados) {
      final idsEspacios = espaciosDelPiso(idPiso)
          .where(
            (espacio) => espaciosSeleccionados.contains(
              int.parse(espacio['id_espacio'].toString()),
            ),
          )
          .map((espacio) => int.parse(espacio['id_espacio'].toString()))
          .toList();

      asignaciones.add({'id_piso': idPiso, 'espacios': idsEspacios});
    }

    setState(() {
      guardando = true;
    });

    try {
      final respuesta = await supabase.rpc(
        'crear_asignacion_sector',

        params: {
          'p_id_usuario': auxiliarId,

          'p_fecha_inicio': fechaInicio.toUtc().toIso8601String(),

          'p_comentario': comentarioController.text.trim(),

          'p_asignaciones': asignaciones,
        },
      );

      debugPrint('RESPUESTA CREAR ASIGNACIÓN: $respuesta');

      if (respuesta is! Map) {
        throw Exception(
          'La respuesta de Supabase no tiene el formato esperado.',
        );
      }

      final Map<String, dynamic> resultado = Map<String, dynamic>.from(
        respuesta,
      );

      if (resultado['ok'] != true) {
        throw Exception('Supabase no confirmó la asignación.');
      }

      final int pisosCreados =
          int.tryParse(resultado['pisos_creados']?.toString() ?? '0') ?? 0;

      final int pisosReutilizados =
          int.tryParse(resultado['pisos_reutilizados']?.toString() ?? '0') ?? 0;

      final int espaciosCreados =
          int.tryParse(resultado['espacios_creados']?.toString() ?? '0') ?? 0;

      final int espaciosYaAsignados =
          int.tryParse(resultado['espacios_ya_asignados']?.toString() ?? '0') ??
          0;

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,

        builder: (context) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Color(0xFF16A34A)),

                SizedBox(width: 10),

                Text('Asignación guardada'),
              ],
            ),

            content: Text(
              '$nombreAuxiliar: '
              '$espaciosCreados '
              '${espaciosCreados == 1 ? 'espacio nuevo agregado' : 'espacios nuevos agregados'}. '
              'Pisos nuevos: $pisosCreados. '
              'Pisos vigentes reutilizados: $pisosReutilizados.'
              '${espaciosYaAsignados > 0 ? ' Espacios que ya estaban asignados: $espaciosYaAsignados.' : ''}',
            ),

            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },

                child: const Text('Aceptar'),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      debugPrint(
        'ERROR RPC ASIGNACIÓN: '
        '${error.message}',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),

          backgroundColor: const Color(0xFFDC2626),
        ),
      );

      // Si ocurrió un conflicto porque alguien
      // asignó un espacio mientras esta pantalla
      // estaba abierta, refrescamos.
      await cargarDatos();
    } catch (error) {
      debugPrint('ERROR GUARDANDO ASIGNACIÓN: $error');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible guardar la asignación.'),

          backgroundColor: Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          guardando = false;
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

          title: const Text('Nueva asignación'),
        ),

        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (mensajeError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),

        appBar: AppBar(
          backgroundColor: Colors.white,

          title: const Text('Nueva asignación'),
        ),

        body: Center(
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

                Text(mensajeError!, textAlign: TextAlign.center),

                const SizedBox(height: 18),

                ElevatedButton.icon(
                  onPressed: cargarDatos,

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

        title: const Text(
          'Nueva asignación',

          style: TextStyle(
            fontWeight: FontWeight.bold,

            color: Color(0xFF1F2937),
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 50),

          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 750),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  const Text(
                    'Asignar sector de trabajo',

                    style: TextStyle(
                      fontSize: 25,

                      fontWeight: FontWeight.bold,

                      color: Color(0xFF1F2937),
                    ),
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    'Selecciona el Auxiliar, edificio y pisos. RegiServ incluirá automáticamente los espacios disponibles de cada piso.',

                    style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
                  ),

                  const SizedBox(height: 26),

                  // ===========================================
                  // AUXILIAR
                  // ===========================================
                  const _TituloSeccion(numero: 1, titulo: 'Auxiliar'),

                  const SizedBox(height: 14),

                  DropdownButtonFormField<String>(
                    value: auxiliarId,

                    isExpanded: true,

                    decoration: _decoracion(
                      'Seleccionar Auxiliar',
                      Icons.person_outline,
                    ),

                    items: auxiliares.map((auxiliar) {
                      return DropdownMenuItem<String>(
                        value: auxiliar['id_usuario'].toString(),

                        child: Text(nombreCompleto(auxiliar)),
                      );
                    }).toList(),

                    onChanged: guardando
                        ? null
                        : (valor) {
                            setState(() {
                              auxiliarId = valor;

                              pisosSeleccionados.clear();
                              espaciosSeleccionados.clear();
                            });
                          },
                  ),

                  if (auxiliares.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),

                      child: Text(
                        'No existen Auxiliares activos.',

                        style: TextStyle(color: Color(0xFFDC2626)),
                      ),
                    ),

                  const SizedBox(height: 26),

                  // ===========================================
                  // EDIFICIO
                  // ===========================================
                  const _TituloSeccion(numero: 2, titulo: 'Edificio'),

                  const SizedBox(height: 14),

                  DropdownButtonFormField<int>(
                    value: edificioId,

                    isExpanded: true,

                    decoration: _decoracion(
                      'Seleccionar edificio',
                      Icons.apartment_outlined,
                    ),

                    items: edificios.map((edificio) {
                      return DropdownMenuItem<int>(
                        value: int.parse(edificio['id_edificio'].toString()),

                        child: Text(
                          '${edificio['nombre']} '
                          '(${edificio['codigo']})',
                        ),
                      );
                    }).toList(),

                    onChanged: guardando ? null : seleccionarEdificio,
                  ),

                  const SizedBox(height: 26),

                  // ===========================================
                  // PISOS
                  // ===========================================
                  const _TituloSeccion(numero: 3, titulo: 'Pisos y espacios'),

                  const SizedBox(height: 8),

                  const Text(
                    'Al seleccionar un piso se incluirán automáticamente sus espacios disponibles. Puedes excluir espacios antes de guardar.',

                    style: TextStyle(
                      fontSize: 13,

                      color: Color(0xFF6B7280),

                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (edificioId == null)
                    const _MensajeVacio(
                      texto: 'Selecciona primero un edificio.',
                    )
                  else if (pisosDelEdificio.isEmpty)
                    const _MensajeVacio(
                      texto: 'Este edificio no tiene pisos activos.',
                    )
                  else
                    for (final piso in pisosDelEdificio)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),

                        child: _TarjetaPisoAsignacion(
                          piso: piso,

                          seleccionado: pisosSeleccionados.contains(
                            int.parse(piso['id_piso'].toString()),
                          ),

                          espacios: espaciosDelPiso(
                            int.parse(piso['id_piso'].toString()),
                          ),

                          espaciosSeleccionados: espaciosSeleccionados,

                          ocupados: espaciosOcupados,

                          ocupantePorEspacio: ocupantePorEspacio,

                          usuarioPorEspacio: usuarioPorEspacio,

                          auxiliarId: auxiliarId,

                          onCambiarPiso: (valor) {
                            cambiarSeleccionPiso(
                              int.parse(piso['id_piso'].toString()),
                              valor,
                            );
                          },

                          onCambiarEspacio: cambiarSeleccionEspacio,

                          onSeleccionarTodos: () {
                            seleccionarTodosPiso(
                              int.parse(piso['id_piso'].toString()),
                            );
                          },

                          onQuitarTodos: () {
                            quitarTodosPiso(
                              int.parse(piso['id_piso'].toString()),
                            );
                          },
                        ),
                      ),

                  const SizedBox(height: 12),

                  // ===========================================
                  // VIGENCIA
                  // ===========================================
                  const _TituloSeccion(numero: 4, titulo: 'Vigencia'),

                  const SizedBox(height: 14),

                  InkWell(
                    onTap: guardando ? null : seleccionarFecha,

                    child: InputDecorator(
                      decoration: _decoracion(
                        'Fecha de inicio',
                        Icons.calendar_today_outlined,
                      ),

                      child: Text(formatearFecha(fechaInicio)),
                    ),
                  ),

                  const SizedBox(height: 14),

                  TextField(
                    controller: comentarioController,

                    enabled: !guardando,

                    maxLines: 3,

                    decoration: _decoracion(
                      'Comentario opcional',
                      Icons.notes_outlined,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ===========================================
                  // RESUMEN
                  // ===========================================
                  Container(
                    width: double.infinity,

                    padding: const EdgeInsets.all(16),

                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),

                      borderRadius: BorderRadius.circular(14),
                    ),

                    child: Wrap(
                      spacing: 24,
                      runSpacing: 8,

                      children: [
                        Text(
                          '${pisosSeleccionados.length} '
                          '${pisosSeleccionados.length == 1 ? 'piso' : 'pisos'} seleccionados',
                        ),

                        Text(
                          '${espaciosSeleccionados.length} '
                          '${espaciosSeleccionados.length == 1 ? 'espacio' : 'espacios'} seleccionados',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,

                    height: 54,

                    child: ElevatedButton.icon(
                      onPressed: guardando ? null : guardar,

                      icon: guardando
                          ? const SizedBox(
                              width: 20,
                              height: 20,

                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,

                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.assignment_ind_outlined),

                      label: Text(
                        guardando
                            ? 'Guardando asignación...'
                            : 'Guardar asignación',

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
    );
  }

  InputDecoration _decoracion(String etiqueta, IconData icono) {
    return InputDecoration(
      labelText: etiqueta,

      prefixIcon: Icon(icono),

      filled: true,

      fillColor: Colors.white,

      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

// =================================================================
// TARJETA PISO
// =================================================================

class _TarjetaPisoAsignacion extends StatelessWidget {
  final Map<String, dynamic> piso;

  final bool seleccionado;

  final List<Map<String, dynamic>> espacios;

  final Set<int> espaciosSeleccionados;

  final Set<String> ocupados;

  final Map<String, String> ocupantePorEspacio;

  final Map<String, String> usuarioPorEspacio;

  final String? auxiliarId;

  final ValueChanged<bool> onCambiarPiso;

  final void Function(int idEspacio, bool seleccionado) onCambiarEspacio;

  final VoidCallback onSeleccionarTodos;

  final VoidCallback onQuitarTodos;

  const _TarjetaPisoAsignacion({
    required this.piso,
    required this.seleccionado,
    required this.espacios,
    required this.espaciosSeleccionados,
    required this.ocupados,
    required this.ocupantePorEspacio,
    required this.usuarioPorEspacio,
    required this.auxiliarId,
    required this.onCambiarPiso,
    required this.onCambiarEspacio,
    required this.onSeleccionarTodos,
    required this.onQuitarTodos,
  });

  @override
  Widget build(BuildContext context) {
    final int libres = espacios
        .where(
          (espacio) =>
              usuarioPorEspacio[espacio['id_espacio'].toString()] == null,
        )
        .length;

    final int yaAsignados = auxiliarId == null
        ? 0
        : espacios
              .where(
                (espacio) =>
                    usuarioPorEspacio[espacio['id_espacio'].toString()] ==
                    auxiliarId,
              )
              .length;

    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(15),

        border: Border.all(
          color: seleccionado
              ? const Color(0xFF7C3AED)
              : const Color(0xFFE5E7EB),

          width: seleccionado ? 1.5 : 1,
        ),
      ),

      child: Column(
        children: [
          CheckboxListTile(
            value: seleccionado,

            onChanged: libres == 0
                ? null
                : (valor) {
                    onCambiarPiso(valor ?? false);
                  },

            title: Text(
              'Piso ${piso['numero_nivel']}',

              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

            subtitle: Text(
              auxiliarId != null && yaAsignados > 0
                  ? '${espacios.length} espacios · '
                        '$libres disponibles · '
                        '$yaAsignados ya asignados a este Auxiliar'
                  : '${espacios.length} espacios · '
                        '$libres disponibles',
            ),

            secondary: const Icon(Icons.layers_outlined),
          ),

          if (seleccionado) ...[
            const Divider(height: 1),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),

              child: Row(
                children: [
                  TextButton(
                    onPressed: onSeleccionarTodos,

                    child: const Text('Seleccionar disponibles'),
                  ),

                  TextButton(
                    onPressed: onQuitarTodos,

                    child: const Text('Quitar selección'),
                  ),
                ],
              ),
            ),

            if (espacios.isEmpty)
              const Padding(
                padding: EdgeInsets.all(18),

                child: Text(
                  'Este piso todavía no tiene espacios configurados.',
                ),
              )
            else
              for (final espacio in espacios)
                _FilaEspacioAsignacion(
                  espacio: espacio,

                  seleccionado: espaciosSeleccionados.contains(
                    int.parse(espacio['id_espacio'].toString()),
                  ),

                  yaAsignadoAlAuxiliar:
                      auxiliarId != null &&
                      usuarioPorEspacio[espacio['id_espacio'].toString()] ==
                          auxiliarId,

                  ocupadoPorOtro:
                      usuarioPorEspacio[espacio['id_espacio'].toString()] !=
                          null &&
                      usuarioPorEspacio[espacio['id_espacio'].toString()] !=
                          auxiliarId,

                  nombreOcupante:
                      ocupantePorEspacio[espacio['id_espacio'].toString()],

                  onChanged: (valor) {
                    onCambiarEspacio(
                      int.parse(espacio['id_espacio'].toString()),
                      valor,
                    );
                  },
                ),

            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

// =================================================================
// FILA ESPACIO
// =================================================================

class _FilaEspacioAsignacion extends StatelessWidget {
  final Map<String, dynamic> espacio;

  final bool seleccionado;
  final bool yaAsignadoAlAuxiliar;
  final bool ocupadoPorOtro;

  final String? nombreOcupante;

  final ValueChanged<bool> onChanged;

  const _FilaEspacioAsignacion({
    required this.espacio,
    required this.seleccionado,
    required this.yaAsignadoAlAuxiliar,
    required this.ocupadoPorOtro,
    required this.nombreOcupante,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      dense: true,

      value: yaAsignadoAlAuxiliar ? true : seleccionado,

      onChanged: yaAsignadoAlAuxiliar || ocupadoPorOtro
          ? null
          : (valor) {
              onChanged(valor ?? false);
            },

      title: Text(espacio['nombreVisible'].toString()),

      subtitle: yaAsignadoAlAuxiliar
          ? const Text(
              'Ya asignado a este Auxiliar',
              style: TextStyle(
                color: Color(0xFF16A34A),
                fontWeight: FontWeight.w600,
              ),
            )
          : ocupadoPorOtro
          ? Text(
              'Asignado a '
              '${nombreOcupante ?? 'otro Auxiliar'}',
              style: const TextStyle(color: Color(0xFFDC2626)),
            )
          : Text(
              '${espacio['tipo']} · '
              '${espacio['codigo']}',
            ),

      secondary: yaAsignadoAlAuxiliar
          ? const Icon(Icons.check_circle_outline, color: Color(0xFF16A34A))
          : ocupadoPorOtro
          ? const Icon(Icons.lock_outline, color: Color(0xFFDC2626))
          : null,
    );
  }
}

// =================================================================
// TITULO
// =================================================================

class _TituloSeccion extends StatelessWidget {
  final int numero;
  final String titulo;

  const _TituloSeccion({required this.numero, required this.titulo});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 16,

          backgroundColor: const Color(0xFF7C3AED),

          foregroundColor: Colors.white,

          child: Text(numero.toString()),
        ),

        const SizedBox(width: 10),

        Text(
          titulo,

          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _MensajeVacio extends StatelessWidget {
  final String texto;

  const _MensajeVacio({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(12),
      ),

      child: Text(texto, style: const TextStyle(color: Color(0xFF6B7280))),
    );
  }
}
