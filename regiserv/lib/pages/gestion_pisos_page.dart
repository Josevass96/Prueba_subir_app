import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GestionPisosPage extends StatefulWidget {
  const GestionPisosPage({super.key});

  @override
  State<GestionPisosPage> createState() => _GestionPisosPageState();
}

class _GestionPisosPageState extends State<GestionPisosPage> {
  final TextEditingController buscarController = TextEditingController();

  SupabaseClient get supabase => Supabase.instance.client;

  // =============================================================
  // DATOS
  // =============================================================

  List<Map<String, dynamic>> pisos = [];

  String filtroEstado = 'Todos';

  String textoBusqueda = '';

  bool cargando = true;

  String? mensajeError;

  String? pisoProcesando;

  // =============================================================
  // INICIALIZACIÓN
  // =============================================================

  @override
  void initState() {
    super.initState();

    cargarPisos();
  }

  @override
  void dispose() {
    buscarController.dispose();

    super.dispose();
  }

  // =============================================================
  // CARGAR PISOS REALES DESDE SUPABASE
  // =============================================================

  Future<void> cargarPisos() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;
      });
    }

    try {
      // ---------------------------------------------------------
      // EDIFICIOS
      // ---------------------------------------------------------

      final edificiosData = await supabase
          .from('edificio')
          .select(
            'id_edificio, '
            'nombre, '
            'codigo, '
            'activo',
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
            'numero_nivel, '
            'activo',
          )
          .order('numero_nivel');

      final List<Map<String, dynamic>> pisosTemporales = [];

      for (final fila in pisosData) {
        final piso = Map<String, dynamic>.from(fila);

        final edificio = edificiosPorId[piso['id_edificio'].toString()];

        pisosTemporales.add({
          ...piso,

          // ---------------------------------------------------
          // CLAVES DE APOYO PARA LA INTERFAZ
          // ---------------------------------------------------
          'numero': piso['numero_nivel'].toString(),

          'edificioNombre':
              edificio?['nombre']?.toString() ?? 'Edificio no encontrado',

          'edificioCodigo': edificio?['codigo']?.toString() ?? '-',

          'edificioActivo': edificio?['activo'] == true,
        });
      }

      // ---------------------------------------------------------
      // ORDENAR POR EDIFICIO Y LUEGO PISO
      // ---------------------------------------------------------

      pisosTemporales.sort((a, b) {
        final edificioA = a['edificioNombre'].toString().toLowerCase();

        final edificioB = b['edificioNombre'].toString().toLowerCase();

        final comparacionEdificio = edificioA.compareTo(edificioB);

        if (comparacionEdificio != 0) {
          return comparacionEdificio;
        }

        final numeroA = int.tryParse(a['numero'].toString()) ?? 0;

        final numeroB = int.tryParse(b['numero'].toString()) ?? 0;

        return numeroA.compareTo(numeroB);
      });

      if (!mounted) {
        return;
      }

      setState(() {
        pisos = pisosTemporales;

        cargando = false;
      });
    } catch (error) {
      debugPrint('ERROR CARGANDO PISOS: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;

        mensajeError = 'No fue posible cargar los pisos desde Supabase.';
      });
    }
  }

  // =============================================================
  // FILTRAR PISOS
  // =============================================================

  List<Map<String, dynamic>> get pisosFiltrados {
    return pisos.where((piso) {
      final activo = piso['activo'] == true;

      final cumpleEstado =
          filtroEstado == 'Todos' ||
          (filtroEstado == 'Activos' && activo) ||
          (filtroEstado == 'Inactivos' && !activo);

      final busqueda = textoBusqueda.trim().toLowerCase();

      final edificioNombre = (piso['edificioNombre'] ?? '')
          .toString()
          .toLowerCase();

      final edificioCodigo = (piso['edificioCodigo'] ?? '')
          .toString()
          .toLowerCase();

      final numero = (piso['numero'] ?? '').toString().toLowerCase();

      final cumpleBusqueda =
          busqueda.isEmpty ||
          edificioNombre.contains(busqueda) ||
          edificioCodigo.contains(busqueda) ||
          numero.contains(busqueda) ||
          'piso $numero'.contains(busqueda);

      return cumpleEstado && cumpleBusqueda;
    }).toList();
  }

  // =============================================================
  // AGREGAR ESPACIOS A UN PISO EXISTENTE
  // =============================================================

  Future<void> agregarEspaciosPiso(Map<String, dynamic> piso) async {
    List<Map<String, dynamic>> tipos;
    try {
      final respuesta = await supabase
          .from('tipo_espacio')
          .select('id_tipo_espacio, nombre')
          .eq('activo', true)
          .order('nombre');
      tipos = respuesta
          .map<Map<String, dynamic>>((fila) => Map<String, dynamic>.from(fila))
          .toList();
    } catch (e) {
      debugPrint('ERROR CARGANDO TIPOS PARA ESPACIOS: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible cargar los tipos de espacio.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    if (tipos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay tipos de espacio activos.')),
      );
      return;
    }

    final desdeController = TextEditingController();
    final hastaController = TextEditingController();
    final cantidadController = TextEditingController(text: '1');
    bool sinNumeracion = false;
    String tipo = tipos.first['nombre'].toString();
    String? errorFormulario;
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Agregar espacios al piso'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Edificio: ${piso['edificioNombre']} · Piso ${piso['numero']}',
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: tipo,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de espacio',
                      border: OutlineInputBorder(),
                    ),
                    items: tipos
                        .map(
                          (e) => DropdownMenuItem<String>(
                            value: e['nombre'].toString(),
                            child: Text(e['nombre'].toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (valor) {
                      if (valor != null) setDialogState(() => tipo = valor);
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sin numeración'),
                    subtitle: const Text(
                      'Ej.: Baño, Biblioteca, Bodega (sin número visible).',
                    ),
                    value: sinNumeracion,
                    onChanged: (valor) => setDialogState(() {
                      sinNumeracion = valor;
                      errorFormulario = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  if (sinNumeracion)
                    TextField(
                      controller: cantidadController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cantidad de espacios (1 a 99)',
                        border: OutlineInputBorder(),
                      ),
                    )
                  else ...[
                    TextField(
                      controller: desdeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Número inicial (1 a 99)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hastaController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Número final (igual si es uno solo)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (errorFormulario != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorFormulario!,
                      style: const TextStyle(color: Color(0xFFDC2626)),
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Text(
                    'No se cambiarán los espacios ya existentes. Los nuevos requerirán configurar NFC y GPS.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Agregar espacios'),
              onPressed: () {
                if (sinNumeracion) {
                  final cantidad = int.tryParse(cantidadController.text.trim());
                  if (cantidad == null || cantidad < 1 || cantidad > 99) {
                    setDialogState(
                      () => errorFormulario =
                          'Ingresa una cantidad entre 1 y 99.',
                    );
                    return;
                  }
                  Navigator.pop(context, {
                    'tipo': tipo,
                    'sin_numeracion': true,
                    'cantidad': cantidad,
                  });
                  return;
                }
                final desde = int.tryParse(desdeController.text.trim());
                final hasta = int.tryParse(hastaController.text.trim());
                if (desde == null ||
                    hasta == null ||
                    desde < 1 ||
                    hasta > 99 ||
                    desde > hasta) {
                  setDialogState(
                    () => errorFormulario = 'Usa números entre 1 y 99, con inicio menor o igual al fin.',
                  );
                  return;
                }
                Navigator.pop(context, {
                  'tipo': tipo,
                  'desde': desde,
                  'hasta': hasta,
                });
              },
            ),
          ],
        ),
      ),
    );
    desdeController.dispose();
    hastaController.dispose();
    cantidadController.dispose();

    if (resultado == null || !mounted) return;
    final tipoElegido = resultado['tipo'] as String;
    final sinNumero = resultado['sin_numeracion'] == true;
    final espaciosNuevos = <Map<String, dynamic>>[];
    if (sinNumero) {
      final cantidad = resultado['cantidad'] as int;
      for (var i = 0; i < cantidad; i++) {
        espaciosNuevos.add({
          'tipo': tipoElegido,
          'numero': null,
          'sin_numeracion': true,
        });
      }
    } else {
      final desde = resultado['desde'] as int;
      final hasta = resultado['hasta'] as int;
      for (int numero = desde; numero <= hasta; numero++) {
        espaciosNuevos.add({'tipo': tipoElegido, 'numero': numero});
      }
    }

    setState(() => pisoProcesando = piso['id_piso'].toString());
    try {
      await supabase.rpc(
        'regiserv_agregar_espacios_piso',
        params: {'p_id_piso': piso['id_piso'], 'p_espacios': espaciosNuevos},
      );
      await cargarPisos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Se agregaron ${espaciosNuevos.length} espacio(s) al piso.',
          ),
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
      debugPrint('ERROR AGREGANDO ESPACIOS A PISO: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible agregar espacios.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) setState(() => pisoProcesando = null);
    }
  }

  // =============================================================
  // ACTIVAR / DESACTIVAR
  // =============================================================

  Future<void> cambiarEstado(Map<String, dynamic> piso) async {
    final activo = piso['activo'] == true;

    final confirmar = await showDialog<bool>(
      context: context,

      builder: (context) {
        return AlertDialog(
          title: Text(activo ? 'Desactivar piso' : 'Activar piso'),

          content: Text(
            activo
                ? '¿Deseas desactivar el Piso ${piso['numero']} '
                      'de ${piso['edificioNombre']}? '
                      'El piso conservará todo su historial y sus relaciones anteriores.'
                : '¿Deseas activar nuevamente el Piso ${piso['numero']} '
                      'de ${piso['edificioNombre']}?',
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

    final idPiso = piso['id_piso'];

    setState(() {
      pisoProcesando = idPiso.toString();
    });

    try {
      // ---------------------------------------------------------
      // UPDATE REAL
      // ---------------------------------------------------------

      await supabase
          .from('piso_nivel')
          .update({'activo': !activo})
          .eq('id_piso', idPiso);

      // ---------------------------------------------------------
      // RECARGAR DESDE POSTGRESQL
      // ---------------------------------------------------------

      await cargarPisos();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activo
                ? 'Piso desactivado correctamente.'
                : 'Piso activado correctamente.',
          ),

          backgroundColor: activo
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
        ),
      );
    } catch (error) {
      debugPrint('ERROR CAMBIANDO ESTADO PISO: $error');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible actualizar el estado del piso.'),

          backgroundColor: Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          pisoProcesando = null;
        });
      }
    }
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final lista = pisosFiltrados;

    final cantidadActivos = pisos
        .where((piso) => piso['activo'] == true)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,

        surfaceTintColor: Colors.white,

        title: const Text(
          'Pisos',

          style: TextStyle(
            fontWeight: FontWeight.bold,

            color: Color(0xFF1F2937),
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Actualizar',

            onPressed: cargando ? null : cargarPisos,

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
                      const Text(
                        'Pisos',

                        style: TextStyle(
                          fontSize: 24,

                          fontWeight: FontWeight.bold,

                          color: Color(0xFF1F2937),
                        ),
                      ),

                      const SizedBox(height: 5),

                      const Text(
                        'Consulta y administra los pisos asociados a cada edificio.',

                        style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
                      ),

                      const SizedBox(height: 18),

                      // ===========================================
                      // RESUMEN
                      // ===========================================
                      Container(
                        width: double.infinity,

                        padding: const EdgeInsets.all(14),

                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDFA),

                          borderRadius: BorderRadius.circular(12),
                        ),

                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            const Icon(
                              Icons.layers_outlined,

                              color: Color(0xFF0F766E),
                            ),

                            const SizedBox(width: 10),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [
                                  Text(
                                    '$cantidadActivos pisos activos',

                                    style: const TextStyle(
                                      color: Color(0xFF0F766E),

                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),

                                  const SizedBox(height: 4),

                                  const Text(
                                    'Los pisos se crean automáticamente al registrar la estructura de un edificio.',

                                    style: TextStyle(
                                      fontSize: 13,

                                      color: Color(0xFF0F766E),

                                      height: 1.3,
                                    ),
                                  ),
                                ],
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
                          hintText: 'Buscar por edificio o piso...',

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
                            _FiltroPiso(
                              texto: 'Todos',

                              seleccionado: filtroEstado == 'Todos',

                              onTap: () {
                                setState(() {
                                  filtroEstado = 'Todos';
                                });
                              },
                            ),

                            const SizedBox(width: 8),

                            _FiltroPiso(
                              texto: 'Activos',

                              seleccionado: filtroEstado == 'Activos',

                              onTap: () {
                                setState(() {
                                  filtroEstado = 'Activos';
                                });
                              },
                            ),

                            const SizedBox(width: 8),

                            _FiltroPiso(
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
                          '${lista.length} ${lista.length == 1 ? 'piso encontrado' : 'pisos encontrados'}',

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
                      ? _ErrorPisos(
                          mensaje: mensajeError!,

                          onReintentar: cargarPisos,
                        )
                      : lista.isEmpty
                      ? const _SinPisos()
                      : RefreshIndicator(
                          onRefresh: cargarPisos,

                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),

                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),

                            itemCount: lista.length,

                            itemBuilder: (context, index) {
                              final piso = lista[index];

                              final procesando =
                                  pisoProcesando == piso['id_piso'].toString();

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),

                                child: _TarjetaPiso(
                                  piso: piso,

                                  procesando: procesando,

                                  onCambiarEstado: () {
                                    cambiarEstado(piso);
                                  },
                                  onAgregarEspacios: () {
                                    agregarEspaciosPiso(piso);
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
// TARJETA PISO
// =================================================================

class _TarjetaPiso extends StatelessWidget {
  final Map<String, dynamic> piso;

  final VoidCallback onCambiarEstado;
  final VoidCallback onAgregarEspacios;

  final bool procesando;

  const _TarjetaPiso({
    required this.piso,
    required this.onCambiarEstado,
    required this.onAgregarEspacios,
    required this.procesando,
  });

  @override
  Widget build(BuildContext context) {
    final activo = piso['activo'] == true;

    final edificioActivo = piso['edificioActivo'] == true;

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
          // -----------------------------------------------------
          // ICONO
          // -----------------------------------------------------

          Container(
            width: 50,

            height: 50,

            decoration: BoxDecoration(
              color: const Color(0xFFF0FDFA),

              borderRadius: BorderRadius.circular(12),
            ),

            child: const Icon(
              Icons.layers_outlined,

              color: Color(0xFF0F766E),

              size: 27,
            ),
          ),

          const SizedBox(width: 14),

          // -----------------------------------------------------
          // INFORMACIÓN
          // -----------------------------------------------------
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  'Piso ${piso['numero']}',

                  style: const TextStyle(
                    fontSize: 17,

                    fontWeight: FontWeight.bold,

                    color: Color(0xFF1F2937),
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  '${piso['edificioNombre']} · Código ${piso['edificioCodigo']}',

                  style: const TextStyle(color: Color(0xFF6B7280)),
                ),

                const SizedBox(height: 12),

                Wrap(
                  spacing: 8,

                  runSpacing: 8,

                  children: [
                    // -------------------------------------------------
                    // ESTADO PISO
                    // -------------------------------------------------

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

                      child: Row(
                        mainAxisSize: MainAxisSize.min,

                        children: [
                          Icon(
                            activo
                                ? Icons.check_circle_outline
                                : Icons.block_outlined,

                            size: 17,

                            color: activo
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF6B7280),
                          ),

                          const SizedBox(width: 6),

                          Text(
                            activo ? 'Activo' : 'Inactivo',

                            style: TextStyle(
                              fontSize: 12,

                              fontWeight: FontWeight.w600,

                              color: activo
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // -------------------------------------------------
                    // EDIFICIO INACTIVO
                    // -------------------------------------------------
                    if (!edificioActivo)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,

                          vertical: 6,
                        ),

                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),

                          borderRadius: BorderRadius.circular(20),
                        ),

                        child: const Row(
                          mainAxisSize: MainAxisSize.min,

                          children: [
                            Icon(
                              Icons.apartment_outlined,

                              size: 17,

                              color: Color(0xFFD97706),
                            ),

                            SizedBox(width: 6),

                            Text(
                              'Edificio inactivo',

                              style: TextStyle(
                                fontSize: 12,

                                fontWeight: FontWeight.w600,

                                color: Color(0xFFD97706),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // -----------------------------------------------------
          // MENÚ
          // -----------------------------------------------------
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
                if (valor == 'estado') {
                  onCambiarEstado();
                }
                if (valor == 'agregar_espacios') {
                  onAgregarEspacios();
                }
              },

              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'agregar_espacios',
                  child: Row(
                    children: [
                      Icon(Icons.add_box_outlined),
                      SizedBox(width: 10),
                      Text('Editar / Agregar espacios'),
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

class _FiltroPiso extends StatelessWidget {
  final String texto;

  final bool seleccionado;

  final VoidCallback onTap;

  const _FiltroPiso({
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
          color: seleccionado ? const Color(0xFF0F766E) : Colors.white,

          borderRadius: BorderRadius.circular(20),

          border: Border.all(
            color: seleccionado
                ? const Color(0xFF0F766E)
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

class _ErrorPisos extends StatelessWidget {
  final String mensaje;

  final Future<void> Function() onReintentar;

  const _ErrorPisos({required this.mensaje, required this.onReintentar});

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

            Text(
              mensaje,

              textAlign: TextAlign.center,

              style: const TextStyle(color: Color(0xFF4B5563)),
            ),

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
// SIN PISOS
// =================================================================

class _SinPisos extends StatelessWidget {
  const _SinPisos();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Icon(Icons.layers_outlined, size: 56, color: Color(0xFF9CA3AF)),

            SizedBox(height: 14),

            Text(
              'No se encontraron pisos',

              style: TextStyle(
                fontSize: 18,

                fontWeight: FontWeight.bold,

                color: Color(0xFF1F2937),
              ),
            ),

            SizedBox(height: 6),

            Text(
              'Los pisos se crearán automáticamente cuando registres una estructura de edificio.',

              textAlign: TextAlign.center,

              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
