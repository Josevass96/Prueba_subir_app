import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GestionTiposEspacioPage extends StatefulWidget {
  const GestionTiposEspacioPage({super.key});

  @override
  State<GestionTiposEspacioPage> createState() =>
      _GestionTiposEspacioPageState();
}

class _GestionTiposEspacioPageState extends State<GestionTiposEspacioPage> {
  final TextEditingController buscarController = TextEditingController();

  SupabaseClient get supabase => Supabase.instance.client;

  // =============================================================
  // DATOS
  // =============================================================

  List<Map<String, dynamic>> tipos = [];

  String filtroEstado = 'Todos';
  String textoBusqueda = '';

  bool cargando = true;
  String? mensajeError;
  String? tipoProcesando;

  // =============================================================
  // INICIALIZACIÓN
  // =============================================================

  @override
  void initState() {
    super.initState();

    cargarTipos();
  }

  @override
  void dispose() {
    buscarController.dispose();

    super.dispose();
  }

  // =============================================================
  // CARGAR TIPOS DESDE SUPABASE
  // =============================================================

  Future<void> cargarTipos() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;
      });
    }

    try {
      final data = await supabase
          .from('tipo_espacio')
          .select(
            'id_tipo_espacio, '
            'nombre, '
            'activo',
          )
          .order('nombre');

      final lista = data
          .map<Map<String, dynamic>>((fila) => Map<String, dynamic>.from(fila))
          .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        tipos = lista;
        cargando = false;
      });
    } catch (error) {
      debugPrint('ERROR CARGANDO TIPOS DE ESPACIO: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;

        mensajeError =
            'No fue posible cargar los tipos de espacio desde Supabase.';
      });
    }
  }

  // =============================================================
  // FILTRADO
  // =============================================================

  List<Map<String, dynamic>> get tiposFiltrados {
    return tipos.where((tipo) {
      final activo = tipo['activo'] == true;

      final cumpleEstado =
          filtroEstado == 'Todos' ||
          (filtroEstado == 'Activos' && activo) ||
          (filtroEstado == 'Inactivos' && !activo);

      final busqueda = textoBusqueda.trim().toLowerCase();

      final nombre = (tipo['nombre'] ?? '').toString().toLowerCase();

      final cumpleBusqueda = busqueda.isEmpty || nombre.contains(busqueda);

      return cumpleEstado && cumpleBusqueda;
    }).toList();
  }

  // =============================================================
  // VALIDAR DUPLICADO
  // =============================================================

  bool nombreExiste(String nombre, {dynamic ignorarId}) {
    final nombreNormalizado = nombre.trim().toLowerCase();

    return tipos.any((tipo) {
      if (ignorarId != null &&
          tipo['id_tipo_espacio'].toString() == ignorarId.toString()) {
        return false;
      }

      return (tipo['nombre'] ?? '').toString().trim().toLowerCase() ==
          nombreNormalizado;
    });
  }

  // =============================================================
  // NUEVO TIPO
  // =============================================================

  Future<void> nuevoTipo() async {
    final resultado = await showDialog<String>(
      context: context,
      barrierDismissible: false,

      builder: (context) {
        return _FormularioTipoEspacioDialog(
          titulo: 'Nuevo tipo de espacio',

          textoBoton: 'Crear tipo',

          validarNombre: (nombre) {
            return nombreExiste(nombre);
          },
        );
      },
    );

    if (resultado == null || !mounted) {
      return;
    }

    try {
      await supabase.from('tipo_espacio').insert({
        'nombre': resultado.trim(),

        'activo': true,
      });

      await cargarTipos();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tipo de espacio creado correctamente.'),

          backgroundColor: Color(0xFF16A34A),
        ),
      );
    } on PostgrestException catch (error) {
      debugPrint('ERROR CREANDO TIPO: ${error.message}');

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
      debugPrint('ERROR CREANDO TIPO: $error');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible crear el tipo de espacio.'),

          backgroundColor: Color(0xFFDC2626),
        ),
      );
    }
  }

  // =============================================================
  // EDITAR TIPO
  // =============================================================

  Future<void> editarTipo(Map<String, dynamic> tipo) async {
    final idTipo = tipo['id_tipo_espacio'];

    final resultado = await showDialog<String>(
      context: context,
      barrierDismissible: false,

      builder: (context) {
        return _FormularioTipoEspacioDialog(
          titulo: 'Editar tipo de espacio',

          textoBoton: 'Guardar cambios',

          nombreActual: tipo['nombre'].toString(),

          validarNombre: (nombre) {
            return nombreExiste(nombre, ignorarId: idTipo);
          },
        );
      },
    );

    if (resultado == null || !mounted) {
      return;
    }

    setState(() {
      tipoProcesando = idTipo.toString();
    });

    try {
      await supabase
          .from('tipo_espacio')
          .update({'nombre': resultado.trim()})
          .eq('id_tipo_espacio', idTipo);

      await cargarTipos();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tipo de espacio actualizado correctamente.'),

          backgroundColor: Color(0xFF16A34A),
        ),
      );
    } on PostgrestException catch (error) {
      debugPrint('ERROR EDITANDO TIPO: ${error.message}');

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
      debugPrint('ERROR EDITANDO TIPO: $error');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible actualizar el tipo de espacio.'),

          backgroundColor: Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          tipoProcesando = null;
        });
      }
    }
  }

  // =============================================================
  // ACTIVAR / DESACTIVAR
  // =============================================================

  Future<void> cambiarEstado(Map<String, dynamic> tipo) async {
    final activo = tipo['activo'] == true;

    final confirmar = await showDialog<bool>(
      context: context,

      builder: (context) {
        return AlertDialog(
          title: Text(
            activo ? 'Desactivar tipo de espacio' : 'Activar tipo de espacio',
          ),

          content: Text(
            activo
                ? '¿Deseas desactivar "${tipo['nombre']}"? '
                      'Los espacios existentes conservarán este tipo, '
                      'pero no se utilizará para crear nuevas estructuras mientras esté inactivo.'
                : '¿Deseas activar nuevamente "${tipo['nombre']}"?',
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
                backgroundColor: activo
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF16A34A),

                foregroundColor: Colors.white,
              ),

              child: Text(activo ? 'Desactivar' : 'Activar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      return;
    }

    final idTipo = tipo['id_tipo_espacio'];

    setState(() {
      tipoProcesando = idTipo.toString();
    });

    try {
      await supabase
          .from('tipo_espacio')
          .update({'activo': !activo})
          .eq('id_tipo_espacio', idTipo);

      await cargarTipos();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activo
                ? 'Tipo de espacio desactivado correctamente.'
                : 'Tipo de espacio activado correctamente.',
          ),

          backgroundColor: activo
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
        ),
      );
    } catch (error) {
      debugPrint('ERROR CAMBIANDO ESTADO TIPO: $error');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No fue posible actualizar el estado del tipo de espacio.',
          ),

          backgroundColor: Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          tipoProcesando = null;
        });
      }
    }
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final lista = tiposFiltrados;

    final cantidadActivos = tipos
        .where((tipo) => tipo['activo'] == true)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,

        surfaceTintColor: Colors.white,

        title: const Text(
          'Tipos de espacio',

          style: TextStyle(
            fontWeight: FontWeight.bold,

            color: Color(0xFF1F2937),
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Actualizar',

            onPressed: cargando ? null : cargarTipos,

            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 750),

            child: Column(
              children: [
                // =================================================
                // CABECERA
                // =================================================

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [
                                Text(
                                  'Tipos de espacio',

                                  style: TextStyle(
                                    fontSize: 24,

                                    fontWeight: FontWeight.bold,

                                    color: Color(0xFF1F2937),
                                  ),
                                ),

                                SizedBox(height: 5),

                                Text(
                                  'Administra las categorías utilizadas para clasificar los espacios físicos.',

                                  style: TextStyle(
                                    color: Color(0xFF6B7280),

                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 12),

                          ElevatedButton.icon(
                            onPressed: nuevoTipo,

                            icon: const Icon(Icons.add_outlined),

                            label: const Text('Nuevo'),

                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD97706),

                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // ===========================================
                      // INFORMACIÓN
                      // ===========================================
                      Container(
                        width: double.infinity,

                        padding: const EdgeInsets.all(14),

                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),

                          borderRadius: BorderRadius.circular(12),
                        ),

                        child: Row(
                          children: [
                            const Icon(
                              Icons.category_outlined,

                              color: Color(0xFFD97706),
                            ),

                            const SizedBox(width: 10),

                            Expanded(
                              child: Text(
                                '$cantidadActivos tipos de espacio activos',

                                style: const TextStyle(
                                  color: Color(0xFF92400E),

                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ===========================================
                      // BUSCADOR
                      // ===========================================
                      TextField(
                        controller: buscarController,

                        decoration: InputDecoration(
                          hintText: 'Buscar tipo de espacio...',

                          prefixIcon: const Icon(Icons.search),

                          suffixIcon: textoBusqueda.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    buscarController.clear();

                                    setState(() {
                                      textoBusqueda = '';
                                    });
                                  },

                                  icon: const Icon(Icons.close),
                                )
                              : null,

                          filled: true,

                          fillColor: Colors.white,

                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),

                        onChanged: (valor) {
                          setState(() {
                            textoBusqueda = valor;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      // ===========================================
                      // FILTROS
                      // ===========================================
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,

                        child: Row(
                          children: [
                            _FiltroTipo(
                              texto: 'Todos',

                              seleccionado: filtroEstado == 'Todos',

                              onTap: () {
                                setState(() {
                                  filtroEstado = 'Todos';
                                });
                              },
                            ),

                            const SizedBox(width: 8),

                            _FiltroTipo(
                              texto: 'Activos',

                              seleccionado: filtroEstado == 'Activos',

                              onTap: () {
                                setState(() {
                                  filtroEstado = 'Activos';
                                });
                              },
                            ),

                            const SizedBox(width: 8),

                            _FiltroTipo(
                              texto: 'Inactivos',

                              seleccionado: filtroEstado == 'Inactivos',

                              onTap: () {
                                setState(() {
                                  filtroEstado = 'Inactivos';
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      if (!cargando)
                        Text(
                          '${lista.length} ${lista.length == 1 ? 'tipo encontrado' : 'tipos encontrados'}',

                          style: const TextStyle(
                            fontSize: 13,

                            color: Color(0xFF6B7280),
                          ),
                        ),
                    ],
                  ),
                ),

                // =================================================
                // LISTADO
                // =================================================
                Expanded(
                  child: cargando
                      ? const Center(child: CircularProgressIndicator())
                      : mensajeError != null
                      ? _ErrorTipos(
                          mensaje: mensajeError!,

                          onReintentar: cargarTipos,
                        )
                      : lista.isEmpty
                      ? const _SinTipos()
                      : RefreshIndicator(
                          onRefresh: cargarTipos,

                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),

                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),

                            itemCount: lista.length,

                            itemBuilder: (context, index) {
                              final tipo = lista[index];

                              final procesando =
                                  tipoProcesando ==
                                  tipo['id_tipo_espacio'].toString();

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),

                                child: _TarjetaTipo(
                                  tipo: tipo,

                                  procesando: procesando,

                                  onEditar: () {
                                    editarTipo(tipo);
                                  },

                                  onCambiarEstado: () {
                                    cambiarEstado(tipo);
                                  },
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
// FORMULARIO NUEVO / EDITAR
// =================================================================

class _FormularioTipoEspacioDialog extends StatefulWidget {
  final String titulo;
  final String textoBoton;

  final String? nombreActual;

  final bool Function(String nombre) validarNombre;

  const _FormularioTipoEspacioDialog({
    required this.titulo,
    required this.textoBoton,
    required this.validarNombre,
    this.nombreActual,
  });

  @override
  State<_FormularioTipoEspacioDialog> createState() =>
      _FormularioTipoEspacioDialogState();
}

class _FormularioTipoEspacioDialogState
    extends State<_FormularioTipoEspacioDialog> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  late TextEditingController nombreController;

  @override
  void initState() {
    super.initState();

    nombreController = TextEditingController(text: widget.nombreActual ?? '');
  }

  @override
  void dispose() {
    nombreController.dispose();

    super.dispose();
  }

  void guardar() {
    if (!formKey.currentState!.validate()) {
      return;
    }

    Navigator.pop(context, nombreController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),

      content: SizedBox(
        width: 430,

        child: Form(
          key: formKey,

          child: Column(
            mainAxisSize: MainAxisSize.min,

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              const Text(
                'El tipo de espacio se utilizará para clasificar lugares como salas, laboratorios, baños u oficinas.',

                style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: nombreController,

                textCapitalization: TextCapitalization.words,

                decoration: InputDecoration(
                  labelText: 'Nombre *',

                  hintText: 'Ej.: Laboratorio',

                  prefixIcon: const Icon(Icons.category_outlined),

                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),

                validator: (valor) {
                  if (valor == null || valor.trim().isEmpty) {
                    return 'Ingresa el nombre del tipo de espacio.';
                  }

                  if (widget.validarNombre(valor)) {
                    return 'Ya existe un tipo de espacio con este nombre.';
                  }

                  return null;
                },
              ),
            ],
          ),
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
          onPressed: guardar,

          icon: Icon(
            widget.nombreActual == null
                ? Icons.add_outlined
                : Icons.save_outlined,
          ),

          label: Text(widget.textoBoton),

          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD97706),

            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

// =================================================================
// TARJETA
// =================================================================

class _TarjetaTipo extends StatelessWidget {
  final Map<String, dynamic> tipo;

  final VoidCallback onEditar;
  final VoidCallback onCambiarEstado;

  final bool procesando;

  const _TarjetaTipo({
    required this.tipo,
    required this.onEditar,
    required this.onCambiarEstado,
    required this.procesando,
  });

  @override
  Widget build(BuildContext context) {
    final activo = tipo['activo'] == true;

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),

      child: Row(
        children: [
          Container(
            width: 50,

            height: 50,

            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),

              borderRadius: BorderRadius.circular(12),
            ),

            child: const Icon(
              Icons.category_outlined,

              color: Color(0xFFD97706),
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  tipo['nombre'].toString(),

                  style: const TextStyle(
                    fontSize: 17,

                    fontWeight: FontWeight.bold,

                    color: Color(0xFF1F2937),
                  ),
                ),

                const SizedBox(height: 10),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,

                    vertical: 6,
                  ),

                  decoration: BoxDecoration(
                    color: activo
                        ? const Color(0xFFF0FDF4)
                        : const Color(0xFFF3F4F6),

                    borderRadius: BorderRadius.circular(20),
                  ),

                  child: Text(
                    activo ? 'Activo' : 'Inactivo',

                    style: TextStyle(
                      fontSize: 12,

                      fontWeight: FontWeight.w600,

                      color: activo
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
              icon: const Icon(Icons.more_vert),

              onSelected: (valor) {
                if (valor == 'editar') {
                  onEditar();
                }

                if (valor == 'estado') {
                  onCambiarEstado();
                }
              },

              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'editar',

                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined),

                      SizedBox(width: 10),

                      Text('Editar'),
                    ],
                  ),
                ),

                PopupMenuItem(
                  value: 'estado',

                  child: Row(
                    children: [
                      Icon(
                        activo
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,

                        color: activo
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF16A34A),
                      ),

                      const SizedBox(width: 10),

                      Text(activo ? 'Desactivar' : 'Activar'),
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
// FILTRO
// =================================================================

class _FiltroTipo extends StatelessWidget {
  final String texto;
  final bool seleccionado;
  final VoidCallback onTap;

  const _FiltroTipo({
    required this.texto,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,

      borderRadius: BorderRadius.circular(20),

      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),

        decoration: BoxDecoration(
          color: seleccionado ? const Color(0xFFD97706) : Colors.white,

          borderRadius: BorderRadius.circular(20),

          border: Border.all(
            color: seleccionado
                ? const Color(0xFFD97706)
                : const Color(0xFFD1D5DB),
          ),
        ),

        child: Text(
          texto,

          style: TextStyle(
            fontSize: 13,

            fontWeight: FontWeight.w600,

            color: seleccionado ? Colors.white : const Color(0xFF4B5563),
          ),
        ),
      ),
    );
  }
}

// =================================================================
// ERROR
// =================================================================

class _ErrorTipos extends StatelessWidget {
  final String mensaje;

  final Future<void> Function() onReintentar;

  const _ErrorTipos({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            const Icon(
              Icons.cloud_off_outlined,

              size: 56,

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

// =================================================================
// SIN RESULTADOS
// =================================================================

class _SinTipos extends StatelessWidget {
  const _SinTipos();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Icon(Icons.category_outlined, size: 56, color: Color(0xFF9CA3AF)),

            SizedBox(height: 14),

            Text(
              'No se encontraron tipos de espacio',

              style: TextStyle(
                fontSize: 18,

                fontWeight: FontWeight.bold,

                color: Color(0xFF1F2937),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
