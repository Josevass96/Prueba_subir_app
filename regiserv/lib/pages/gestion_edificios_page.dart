import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'asistente_estructura_page.dart';

class GestionEdificiosPage extends StatefulWidget {
  const GestionEdificiosPage({super.key});

  @override
  State<GestionEdificiosPage> createState() => _GestionEdificiosPageState();
}

class _GestionEdificiosPageState extends State<GestionEdificiosPage> {
  final TextEditingController buscarController = TextEditingController();

  SupabaseClient get supabase => Supabase.instance.client;

  List<Map<String, dynamic>> edificios = [];

  String filtroEstado = 'Todos';

  String textoBusqueda = '';

  bool cargando = true;

  String? mensajeError;

  String? edificioProcesando;

  // =============================================================
  // INICIALIZACIÓN
  // =============================================================

  @override
  void initState() {
    super.initState();

    cargarEdificios();
  }

  @override
  void dispose() {
    buscarController.dispose();

    super.dispose();
  }

  // =============================================================
  // CARGAR EDIFICIOS
  // =============================================================

  Future<void> cargarEdificios() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;
      });
    }

    try {
      final data = await supabase
          .from('edificio')
          .select(
            'id_edificio, '
            'id_sede, '
            'codigo, '
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
        edificios = lista;

        cargando = false;
      });
    } catch (error) {
      debugPrint('ERROR CARGANDO EDIFICIOS: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;

        mensajeError = 'No fue posible cargar los edificios desde Supabase.';
      });
    }
  }

  // =============================================================
  // FILTRADO
  // =============================================================

  List<Map<String, dynamic>> get edificiosFiltrados {
    return edificios.where((edificio) {
      final activo = edificio['activo'] == true;

      final cumpleEstado =
          filtroEstado == 'Todos' ||
          (filtroEstado == 'Activos' && activo) ||
          (filtroEstado == 'Inactivos' && !activo);

      final busqueda = textoBusqueda.trim().toLowerCase();

      final nombre = (edificio['nombre'] ?? '').toString().toLowerCase();

      final codigo = (edificio['codigo'] ?? '').toString().toLowerCase();

      final cumpleBusqueda =
          busqueda.isEmpty ||
          nombre.contains(busqueda) ||
          codigo.contains(busqueda);

      return cumpleEstado && cumpleBusqueda;
    }).toList();
  }

  // =============================================================
  // NUEVA ESTRUCTURA
  // =============================================================

  Future<void> nuevoEdificio() async {
    final creado = await Navigator.push<bool>(
      context,

      MaterialPageRoute(builder: (context) => const AsistenteEstructuraPage()),
    );

    if (creado != true || !mounted) {
      return;
    }

    await cargarEdificios();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Estructura creada correctamente.'),

        backgroundColor: Color(0xFF16A34A),
      ),
    );
  }

  // =============================================================
  // EDITAR EDIFICIO
  // =============================================================

  Future<void> editarEdificio(Map<String, dynamic> edificio) async {
    final resultado = await showDialog<String>(
      context: context,
      barrierDismissible: false,

      builder: (context) {
        return _EditarEdificioDialog(
          nombreActual: edificio['nombre'].toString(),

          codigo: edificio['codigo'].toString(),
        );
      },
    );

    if (resultado == null || !mounted) {
      return;
    }

    // Amplia un edificio existente sin recrear sus pisos ni espacios.
    if (resultado == '__REGISERV_AGREGAR_PISOS__') {
      await agregarPisosEdificio(edificio);
      return;
    }

    final idEdificio = edificio['id_edificio'];

    setState(() {
      edificioProcesando = idEdificio.toString();
    });

    try {
      await supabase
          .from('edificio')
          .update({'nombre': resultado.trim()})
          .eq('id_edificio', idEdificio);

      await cargarEdificios();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Edificio actualizado correctamente.'),

          backgroundColor: Color(0xFF16A34A),
        ),
      );
    } catch (error) {
      debugPrint('ERROR EDITANDO EDIFICIO: $error');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible actualizar el edificio.'),

          backgroundColor: Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          edificioProcesando = null;
        });
      }
    }
  }

  // =============================================================
  // AGREGAR PISOS A EDIFICIO EXISTENTE
  // =============================================================

  Future<void> agregarPisosEdificio(Map<String, dynamic> edificio) async {
    final controller = TextEditingController();
    String? mensajeValidacion;

    final numeros = await showDialog<List<int>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Agregar pisos'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edificio: ${edificio['nombre']}'),
                const SizedBox(height: 12),
                const Text(
                  'Escribe los números de los nuevos pisos, separados por coma. Ejemplo: 3, 4',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: 'Números de piso (1 a 20)',
                    border: const OutlineInputBorder(),
                    errorText: mensajeValidacion,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Los pisos actuales, espacios y asignaciones no se modificarán.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Agregar'),
              onPressed: () {
                final partes = controller.text
                    .split(',')
                    .map((t) => t.trim())
                    .toList();
                final parsed = partes.map(int.tryParse).toList();
                if (partes.isEmpty ||
                    parsed.any((n) => n == null || n < 1 || n > 20)) {
                  setDialogState(
                    () => mensajeValidacion =
                        'Ingresa números enteros entre 1 y 20.',
                  );
                  return;
                }
                final valores = parsed.cast<int>();
                if (valores.toSet().length != valores.length) {
                  setDialogState(
                    () =>
                        mensajeValidacion = 'No repitas un número en la lista.',
                  );
                  return;
                }
                Navigator.pop(context, valores);
              },
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    if (numeros == null || !mounted) return;

    final idEdificio = edificio['id_edificio'];
    setState(() => edificioProcesando = idEdificio.toString());
    try {
      await supabase.rpc(
        'regiserv_agregar_pisos_edificio',
        params: <String, dynamic>{
          'p_id_edificio': idEdificio,
          'p_numeros_pisos': numeros,
        },
      );
      await cargarEdificios();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Se agregaron ${numeros.length} piso(s) al edificio.'),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    } catch (e) {
      debugPrint('ERROR AGREGANDO PISOS: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible agregar los pisos.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) setState(() => edificioProcesando = null);
    }
  }

  // =============================================================
  // ACTIVAR / DESACTIVAR
  // =============================================================

  Future<void> cambiarEstado(Map<String, dynamic> edificio) async {
    final activo = edificio['activo'] == true;

    final confirmar = await showDialog<bool>(
      context: context,

      builder: (context) {
        return AlertDialog(
          title: Text(activo ? 'Desactivar edificio' : 'Activar edificio'),

          content: Text(
            activo
                ? '¿Deseas desactivar ${edificio['nombre']}? '
                      'El edificio conservará su historial y sus relaciones anteriores.'
                : '¿Deseas activar nuevamente ${edificio['nombre']}?',
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

    final idEdificio = edificio['id_edificio'];

    setState(() {
      edificioProcesando = idEdificio.toString();
    });

    try {
      await supabase
          .from('edificio')
          .update({'activo': !activo})
          .eq('id_edificio', idEdificio);

      await cargarEdificios();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activo
                ? 'Edificio desactivado correctamente.'
                : 'Edificio activado correctamente.',
          ),
        ),
      );
    } catch (error) {
      debugPrint('ERROR CAMBIANDO ESTADO EDIFICIO: $error');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible actualizar el estado del edificio.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          edificioProcesando = null;
        });
      }
    }
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final lista = edificiosFiltrados;

    final cantidadActivos = edificios
        .where((edificio) => edificio['activo'] == true)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,

        surfaceTintColor: Colors.white,

        title: const Text(
          'Edificios',

          style: TextStyle(
            fontWeight: FontWeight.bold,

            color: Color(0xFF1F2937),
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Actualizar',

            onPressed: cargando ? null : cargarEdificios,

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
                                  'Edificios',

                                  style: TextStyle(
                                    fontSize: 24,

                                    fontWeight: FontWeight.bold,

                                    color: Color(0xFF1F2937),
                                  ),
                                ),

                                SizedBox(height: 5),

                                Text(
                                  'Administra los edificios disponibles para los sectores de RegiServ.',

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
                            onPressed: nuevoEdificio,

                            icon: const Icon(Icons.add_business_outlined),

                            label: const Text('Nuevo'),

                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),

                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      Container(
                        width: double.infinity,

                        padding: const EdgeInsets.all(14),

                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),

                          borderRadius: BorderRadius.circular(12),
                        ),

                        child: Row(
                          children: [
                            const Icon(
                              Icons.apartment_outlined,

                              color: Color(0xFF1565C0),
                            ),

                            const SizedBox(width: 10),

                            Text(
                              '$cantidadActivos edificios activos',

                              style: const TextStyle(
                                color: Color(0xFF1E40AF),

                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      TextField(
                        controller: buscarController,

                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre o código...',

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

                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,

                        child: Row(
                          children: [
                            _FiltroEdificio(
                              texto: 'Todos',

                              seleccionado: filtroEstado == 'Todos',

                              onTap: () {
                                setState(() {
                                  filtroEstado = 'Todos';
                                });
                              },
                            ),

                            const SizedBox(width: 8),

                            _FiltroEdificio(
                              texto: 'Activos',

                              seleccionado: filtroEstado == 'Activos',

                              onTap: () {
                                setState(() {
                                  filtroEstado = 'Activos';
                                });
                              },
                            ),

                            const SizedBox(width: 8),

                            _FiltroEdificio(
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
                          '${lista.length} ${lista.length == 1 ? 'edificio encontrado' : 'edificios encontrados'}',

                          style: const TextStyle(
                            fontSize: 13,

                            color: Color(0xFF6B7280),
                          ),
                        ),
                    ],
                  ),
                ),

                Expanded(
                  child: cargando
                      ? const Center(child: CircularProgressIndicator())
                      : mensajeError != null
                      ? _ErrorEdificios(
                          mensaje: mensajeError!,

                          onReintentar: cargarEdificios,
                        )
                      : lista.isEmpty
                      ? const _SinEdificios()
                      : RefreshIndicator(
                          onRefresh: cargarEdificios,

                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),

                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),

                            itemCount: lista.length,

                            itemBuilder: (context, index) {
                              final edificio = lista[index];

                              final procesando =
                                  edificioProcesando ==
                                  edificio['id_edificio'].toString();

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),

                                child: _TarjetaEdificio(
                                  edificio: edificio,

                                  procesando: procesando,

                                  onEditar: () {
                                    editarEdificio(edificio);
                                  },

                                  onCambiarEstado: () {
                                    cambiarEstado(edificio);
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
// EDITAR EDIFICIO
// =================================================================

class _EditarEdificioDialog extends StatefulWidget {
  final String nombreActual;
  final String codigo;

  const _EditarEdificioDialog({
    required this.nombreActual,
    required this.codigo,
  });

  @override
  State<_EditarEdificioDialog> createState() => _EditarEdificioDialogState();
}

class _EditarEdificioDialogState extends State<_EditarEdificioDialog> {
  final formKey = GlobalKey<FormState>();

  late TextEditingController nombreController;

  @override
  void initState() {
    super.initState();

    nombreController = TextEditingController(text: widget.nombreActual);
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
      title: const Text('Editar edificio'),

      content: SizedBox(
        width: 430,

        child: Form(
          key: formKey,

          child: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              TextFormField(
                controller: nombreController,

                textCapitalization: TextCapitalization.words,

                decoration: const InputDecoration(
                  labelText: 'Nombre *',

                  prefixIcon: Icon(Icons.apartment_outlined),

                  border: OutlineInputBorder(),
                ),

                validator: (valor) {
                  if (valor == null || valor.trim().isEmpty) {
                    return 'Ingresa el nombre del edificio.';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                initialValue: widget.codigo,

                readOnly: true,

                decoration: const InputDecoration(
                  labelText: 'Código',

                  helperText: 'El código no puede modificarse.',

                  prefixIcon: Icon(Icons.tag_outlined),

                  filled: true,

                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),

      actions: [
        TextButton.icon(
          onPressed: () => Navigator.pop(context, '__REGISERV_AGREGAR_PISOS__'),
          icon: const Icon(Icons.layers_outlined),
          label: const Text('Agregar pisos'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },

          child: const Text('Cancelar'),
        ),

        ElevatedButton.icon(
          onPressed: guardar,

          icon: const Icon(Icons.save_outlined),

          label: const Text('Guardar cambios'),
        ),
      ],
    );
  }
}

// =================================================================
// TARJETA
// =================================================================

class _TarjetaEdificio extends StatelessWidget {
  final Map<String, dynamic> edificio;

  final VoidCallback onEditar;

  final VoidCallback onCambiarEstado;

  final bool procesando;

  const _TarjetaEdificio({
    required this.edificio,
    required this.onEditar,
    required this.onCambiarEstado,
    required this.procesando,
  });

  @override
  Widget build(BuildContext context) {
    final activo = edificio['activo'] == true;

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
              color: const Color(0xFFEFF6FF),

              borderRadius: BorderRadius.circular(12),
            ),

            child: const Icon(
              Icons.apartment_outlined,

              color: Color(0xFF1565C0),

              size: 27,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  edificio['nombre'].toString(),

                  style: const TextStyle(
                    fontSize: 17,

                    fontWeight: FontWeight.bold,

                    color: Color(0xFF1F2937),
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  'Código: ${edificio['codigo']}',

                  style: const TextStyle(color: Color(0xFF6B7280)),
                ),

                const SizedBox(height: 12),

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

class _FiltroEdificio extends StatelessWidget {
  final String texto;
  final bool seleccionado;
  final VoidCallback onTap;

  const _FiltroEdificio({
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
          color: seleccionado ? const Color(0xFF1565C0) : Colors.white,

          borderRadius: BorderRadius.circular(20),

          border: Border.all(
            color: seleccionado
                ? const Color(0xFF1565C0)
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

class _ErrorEdificios extends StatelessWidget {
  final String mensaje;

  final Future<void> Function() onReintentar;

  const _ErrorEdificios({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,

        children: [
          const Icon(
            Icons.cloud_off_outlined,

            size: 56,

            color: Color(0xFF9CA3AF),
          ),

          const SizedBox(height: 14),

          Text(mensaje),

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
    );
  }
}

// =================================================================
// SIN EDIFICIOS
// =================================================================

class _SinEdificios extends StatelessWidget {
  const _SinEdificios();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Icon(Icons.apartment_outlined, size: 56, color: Color(0xFF9CA3AF)),

            SizedBox(height: 14),

            Text(
              'No se encontraron edificios',

              style: TextStyle(
                fontSize: 18,

                fontWeight: FontWeight.bold,

                color: Color(0xFF1F2937),
              ),
            ),

            SizedBox(height: 6),

            Text(
              'Crea una nueva estructura para comenzar.',

              textAlign: TextAlign.center,

              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
