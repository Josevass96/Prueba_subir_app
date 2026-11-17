import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'configurar_espacio_page.dart';

class GestionEspaciosPage extends StatefulWidget {
  const GestionEspaciosPage({super.key});

  @override
  State<GestionEspaciosPage> createState() => _GestionEspaciosPageState();
}

class _GestionEspaciosPageState extends State<GestionEspaciosPage> {
  final TextEditingController buscarController = TextEditingController();

  SupabaseClient get supabase => Supabase.instance.client;

  List<Map<String, dynamic>> espacios = [];

  String textoBusqueda = '';
  String filtroEstado = 'Todos';

  String? filtroEdificio;
  String? filtroPiso;
  String? filtroTipo;

  bool mostrarFiltros = false;

  bool cargando = true;

  String? mensajeError;

  String? espacioProcesando;

  // =============================================================
  // INICIALIZACIÓN
  // =============================================================

  @override
  void initState() {
    super.initState();

    cargarEspacios();
  }

  @override
  void dispose() {
    buscarController.dispose();

    super.dispose();
  }

  // =============================================================
  // CARGAR ESPACIOS REALES
  // =============================================================

  Future<void> cargarEspacios() async {
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
            'nombre, '
            'activo',
          );

      final Map<String, Map<String, dynamic>> tiposPorId = {};

      for (final fila in tiposData) {
        final tipo = Map<String, dynamic>.from(fila);

        tiposPorId[tipo['id_tipo_espacio'].toString()] = tipo;
      }

      // ---------------------------------------------------------
      // ESTADOS NFC
      // ---------------------------------------------------------

      final estadosNfcData = await supabase
          .from('estado_nfc')
          .select('id_estado_nfc, activo');

      final Set<String> estadosOperativos = {};

      for (final estado in estadosNfcData) {
        if (estado['activo'] == true) {
          estadosOperativos.add(estado['id_estado_nfc'].toString());
        }
      }

      // ---------------------------------------------------------
      // NFC
      // ---------------------------------------------------------

      final nfcData = await supabase
          .from('nfc')
          .select(
            'id_nfc, '
            'id_espacio, '
            'id_estado_nfc, '
            'uid_nfc, '
            'fecha_instalacion, '
            'fecha_retiro',
          );

      final Map<String, Map<String, dynamic>> nfcActivaPorEspacio = {};

      for (final fila in nfcData) {
        final nfc = Map<String, dynamic>.from(fila);

        final vigente = nfc['fecha_retiro'] == null;

        final estadoOperativo = estadosOperativos.contains(
          nfc['id_estado_nfc'].toString(),
        );

        if (vigente && estadoOperativo) {
          nfcActivaPorEspacio[nfc['id_espacio'].toString()] = nfc;
        }
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
            'radio_latitud, '
            'radio_longitud, '
            'radio_metros, '
            'activo',
          );

      final List<Map<String, dynamic>> espaciosTemporales = [];

      for (final fila in espaciosData) {
        final espacio = Map<String, dynamic>.from(fila);

        final piso = pisosPorId[espacio['id_piso'].toString()];

        final edificio = piso == null
            ? null
            : edificiosPorId[piso['id_edificio'].toString()];

        final tipo = tiposPorId[espacio['id_tipo_espacio'].toString()];

        final nfc = nfcActivaPorEspacio[espacio['id_espacio'].toString()];

        final gpsConfigurado =
            espacio['radio_latitud'] != null &&
            espacio['radio_longitud'] != null;

        final nfcConfigurado = nfc != null;

        espaciosTemporales.add({
          ...espacio,

          'nombreVisible': (espacio['nombre'] ?? espacio['codigo'] ?? '')
              .toString(),

          'edificioNombre':
              edificio?['nombre']?.toString() ?? 'Edificio no encontrado',

          'edificioCodigo': edificio?['codigo']?.toString() ?? '-',

          'pisoNumero': piso?['numero_nivel']?.toString() ?? '-',

          'tipo': tipo?['nombre']?.toString() ?? 'Sin tipo',

          'gpsConfigurado': gpsConfigurado,

          'nfcConfigurado': nfcConfigurado,

          'nfcUid': nfc?['uid_nfc']?.toString(),

          'id_nfc': nfc?['id_nfc'],
        });
      }

      espaciosTemporales.sort((a, b) {
        final edificioA = a['edificioCodigo'].toString();

        final edificioB = b['edificioCodigo'].toString();

        final compararEdificio = edificioA.compareTo(edificioB);

        if (compararEdificio != 0) {
          return compararEdificio;
        }

        final pisoA = int.tryParse(a['pisoNumero'].toString()) ?? 0;

        final pisoB = int.tryParse(b['pisoNumero'].toString()) ?? 0;

        final compararPiso = pisoA.compareTo(pisoB);

        if (compararPiso != 0) {
          return compararPiso;
        }

        return a['codigo'].toString().compareTo(b['codigo'].toString());
      });

      if (!mounted) {
        return;
      }

      setState(() {
        espacios = espaciosTemporales;

        cargando = false;
      });
    } catch (error) {
      debugPrint('ERROR CARGANDO ESPACIOS: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;

        mensajeError = 'No fue posible cargar los espacios desde Supabase.';
      });
    }
  }

  // =============================================================
  // EDIFICIOS DISPONIBLES
  // =============================================================

  List<String> get edificiosDisponibles {
    final resultado = espacios
        .map((espacio) => espacio['edificioCodigo'].toString())
        .where((codigo) => codigo != '-')
        .toSet()
        .toList();

    resultado.sort();

    return resultado;
  }

  // =============================================================
  // PISOS DISPONIBLES
  // =============================================================

  List<String> get pisosDisponibles {
    final resultado = espacios
        .where((espacio) {
          if (filtroEdificio == null) {
            return true;
          }

          return espacio['edificioCodigo'].toString() == filtroEdificio;
        })
        .map((espacio) => espacio['pisoNumero'].toString())
        .where((piso) => piso != '-')
        .toSet()
        .toList();

    resultado.sort((a, b) {
      final numeroA = int.tryParse(a) ?? 0;

      final numeroB = int.tryParse(b) ?? 0;

      return numeroA.compareTo(numeroB);
    });

    return resultado;
  }

  // =============================================================
  // TIPOS DISPONIBLES
  // =============================================================

  List<String> get tiposDisponibles {
    final resultado = espacios
        .map((espacio) => espacio['tipo'].toString())
        .where((tipo) => tipo != 'Sin tipo')
        .toSet()
        .toList();

    resultado.sort();

    return resultado;
  }

  // =============================================================
  // FILTRADO
  // =============================================================

  List<Map<String, dynamic>> get espaciosFiltrados {
    return espacios.where((espacio) {
      final activo = espacio['activo'] == true;

      final cumpleEstado =
          filtroEstado == 'Todos' ||
          (filtroEstado == 'Activos' && activo) ||
          (filtroEstado == 'Inactivos' && !activo);

      final cumpleEdificio =
          filtroEdificio == null ||
          espacio['edificioCodigo'].toString() == filtroEdificio;

      final cumplePiso =
          filtroPiso == null || espacio['pisoNumero'].toString() == filtroPiso;

      final cumpleTipo =
          filtroTipo == null || espacio['tipo'].toString() == filtroTipo;

      final busqueda = textoBusqueda.trim().toLowerCase();

      final nombre = espacio['nombreVisible'].toString().toLowerCase();

      final codigo = espacio['codigo'].toString().toLowerCase();

      final tipo = espacio['tipo'].toString().toLowerCase();

      final edificio = espacio['edificioNombre'].toString().toLowerCase();

      final cumpleBusqueda =
          busqueda.isEmpty ||
          nombre.contains(busqueda) ||
          codigo.contains(busqueda) ||
          tipo.contains(busqueda) ||
          edificio.contains(busqueda);

      return cumpleEstado &&
          cumpleEdificio &&
          cumplePiso &&
          cumpleTipo &&
          cumpleBusqueda;
    }).toList();
  }

  // =============================================================
  // LIMPIAR FILTROS
  // =============================================================

  void limpiarFiltros() {
    buscarController.clear();

    setState(() {
      textoBusqueda = '';
      filtroEstado = 'Todos';

      filtroEdificio = null;
      filtroPiso = null;
      filtroTipo = null;
    });
  }

  // =============================================================
  // ACTIVAR / DESACTIVAR
  // =============================================================

  Future<void> cambiarEstado(Map<String, dynamic> espacio) async {
    final activo = espacio['activo'] == true;

    final confirmar = await showDialog<bool>(
      context: context,

      builder: (context) {
        return AlertDialog(
          title: Text(activo ? 'Desactivar espacio' : 'Activar espacio'),

          content: Text(
            activo
                ? '¿Deseas desactivar ${espacio['nombreVisible']}? '
                      'El espacio conservará todo su historial.'
                : '¿Deseas activar nuevamente ${espacio['nombreVisible']}?',
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

    final idEspacio = espacio['id_espacio'];

    setState(() {
      espacioProcesando = idEspacio.toString();
    });

    try {
      await supabase
          .from('espacio')
          .update({'activo': !activo})
          .eq('id_espacio', idEspacio);

      await cargarEspacios();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activo
                ? 'Espacio desactivado correctamente.'
                : 'Espacio activado correctamente.',
          ),
        ),
      );
    } catch (error) {
      debugPrint('ERROR CAMBIANDO ESTADO ESPACIO: $error');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible actualizar el estado del espacio.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          espacioProcesando = null;
        });
      }
    }
  }

  // =============================================================
  // CONFIGURAR
  // =============================================================

  Future<void> configurarEspacio(Map<String, dynamic> espacio) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConfigurarEspacioPage(espacio: espacio),
      ),
    );

    if (!mounted) {
      return;
    }

    await cargarEspacios();
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final lista = espaciosFiltrados;

    final activos = espacios
        .where((espacio) => espacio['activo'] == true)
        .length;

    final pendientesGps = espacios
        .where(
          (espacio) =>
              espacio['activo'] == true && espacio['gpsConfigurado'] != true,
        )
        .length;

    final pendientesNfc = espacios
        .where(
          (espacio) =>
              espacio['activo'] == true && espacio['nfcConfigurado'] != true,
        )
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,

        surfaceTintColor: Colors.white,

        title: const Text(
          'Espacios',

          style: TextStyle(
            fontWeight: FontWeight.bold,

            color: Color(0xFF1F2937),
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Actualizar',

            onPressed: cargando ? null : cargarEspacios,

            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: cargarEspacios,

          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),

            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),

            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 850),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    // =================================================
                    // CABECERA
                    // =================================================

                    const Text(
                      'Espacios físicos',

                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 5),

                    const Text(
                      'Consulta los espacios creados para cada edificio y piso.',

                      style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
                    ),

                    const SizedBox(height: 18),

                    // =================================================
                    // RESUMEN
                    // =================================================
                    _ResumenEspacios(
                      activos: activos,
                      pendientesGps: pendientesGps,
                      pendientesNfc: pendientesNfc,
                    ),

                    const SizedBox(height: 18),

                    // =================================================
                    // BUSCADOR
                    // =================================================
                    TextField(
                      controller: buscarController,

                      decoration: InputDecoration(
                        hintText:
                            'Buscar por nombre, código, edificio o tipo...',

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

                    const SizedBox(height: 12),

                    // =================================================
                    // BOTÓN MOSTRAR / OCULTAR FILTROS
                    // =================================================
                    SizedBox(
                      width: double.infinity,

                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            mostrarFiltros = !mostrarFiltros;
                          });
                        },

                        icon: Icon(
                          mostrarFiltros
                              ? Icons.filter_alt_off_outlined
                              : Icons.filter_alt_outlined,
                        ),

                        label: Text(
                          mostrarFiltros
                              ? 'Ocultar filtros'
                              : 'Mostrar filtros',
                        ),

                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                    // =================================================
                    // FILTROS PLEGABLES
                    // =================================================
                    if (mostrarFiltros) ...[
                      const SizedBox(height: 14),

                      Container(
                        width: double.infinity,

                        padding: const EdgeInsets.all(16),

                        decoration: BoxDecoration(
                          color: Colors.white,

                          borderRadius: BorderRadius.circular(14),

                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),

                        child: Column(
                          children: [
                            // ===========================================
                            // EDIFICIO + PISO RESPONSIVO
                            // ===========================================

                            LayoutBuilder(
                              builder: (context, constraints) {
                                final bool pantallaEstrecha =
                                    constraints.maxWidth < 500;

                                final Widget edificio =
                                    DropdownButtonFormField<String>(
                                      value: filtroEdificio,

                                      isExpanded: true,

                                      decoration: InputDecoration(
                                        labelText: 'Edificio',

                                        prefixIcon: const Icon(
                                          Icons.apartment_outlined,
                                        ),

                                        filled: true,

                                        fillColor: const Color(0xFFF8FAFC),

                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),

                                      items: edificiosDisponibles.map((codigo) {
                                        return DropdownMenuItem<String>(
                                          value: codigo,

                                          child: Text('Edificio $codigo'),
                                        );
                                      }).toList(),

                                      onChanged: (valor) {
                                        setState(() {
                                          filtroEdificio = valor;

                                          filtroPiso = null;
                                        });
                                      },
                                    );

                                final Widget piso =
                                    DropdownButtonFormField<String>(
                                      value: filtroPiso,

                                      isExpanded: true,

                                      decoration: InputDecoration(
                                        labelText: 'Piso',

                                        prefixIcon: const Icon(
                                          Icons.layers_outlined,
                                        ),

                                        filled: true,

                                        fillColor: const Color(0xFFF8FAFC),

                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),

                                      items: pisosDisponibles.map((piso) {
                                        return DropdownMenuItem<String>(
                                          value: piso,

                                          child: Text('Piso $piso'),
                                        );
                                      }).toList(),

                                      onChanged: (valor) {
                                        setState(() {
                                          filtroPiso = valor;
                                        });
                                      },
                                    );

                                if (pantallaEstrecha) {
                                  return Column(
                                    children: [
                                      edificio,

                                      const SizedBox(height: 12),

                                      piso,
                                    ],
                                  );
                                }

                                return Row(
                                  children: [
                                    Expanded(child: edificio),

                                    const SizedBox(width: 12),

                                    Expanded(child: piso),
                                  ],
                                );
                              },
                            ),

                            const SizedBox(height: 12),

                            // ===========================================
                            // TIPO
                            // ===========================================
                            DropdownButtonFormField<String>(
                              value: filtroTipo,

                              isExpanded: true,

                              decoration: InputDecoration(
                                labelText: 'Tipo de espacio',

                                prefixIcon: const Icon(Icons.category_outlined),

                                filled: true,

                                fillColor: const Color(0xFFF8FAFC),

                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),

                              items: tiposDisponibles.map((tipo) {
                                return DropdownMenuItem<String>(
                                  value: tipo,

                                  child: Text(tipo),
                                );
                              }).toList(),

                              onChanged: (valor) {
                                setState(() {
                                  filtroTipo = valor;
                                });
                              },
                            ),

                            const SizedBox(height: 14),

                            // ===========================================
                            // ESTADOS
                            // ===========================================
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,

                              child: Row(
                                children: [
                                  _FiltroEstado(
                                    texto: 'Todos',

                                    seleccionado: filtroEstado == 'Todos',

                                    onTap: () {
                                      setState(() {
                                        filtroEstado = 'Todos';
                                      });
                                    },
                                  ),

                                  const SizedBox(width: 8),

                                  _FiltroEstado(
                                    texto: 'Activos',

                                    seleccionado: filtroEstado == 'Activos',

                                    onTap: () {
                                      setState(() {
                                        filtroEstado = 'Activos';
                                      });
                                    },
                                  ),

                                  const SizedBox(width: 8),

                                  _FiltroEstado(
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

                            const SizedBox(height: 8),

                            Align(
                              alignment: Alignment.centerRight,

                              child: TextButton.icon(
                                onPressed: limpiarFiltros,

                                icon: const Icon(Icons.filter_alt_off_outlined),

                                label: const Text('Limpiar filtros'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // =================================================
                    // CANTIDAD
                    // =================================================
                    if (!cargando)
                      Text(
                        '${lista.length} ${lista.length == 1 ? 'espacio encontrado' : 'espacios encontrados'}',

                        style: const TextStyle(
                          fontSize: 13,

                          color: Color(0xFF6B7280),
                        ),
                      ),

                    const SizedBox(height: 14),

                    // =================================================
                    // CONTENIDO
                    // =================================================
                    if (cargando)
                      const Padding(
                        padding: EdgeInsets.all(40),

                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (mensajeError != null)
                      _ErrorEspacios(
                        mensaje: mensajeError!,

                        onReintentar: cargarEspacios,
                      )
                    else if (lista.isEmpty)
                      const _SinEspacios()
                    else
                      ListView.builder(
                        shrinkWrap: true,

                        physics: const NeverScrollableScrollPhysics(),

                        itemCount: lista.length,

                        itemBuilder: (context, index) {
                          final espacio = lista[index];

                          final procesando =
                              espacioProcesando ==
                              espacio['id_espacio'].toString();

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),

                            child: _TarjetaEspacio(
                              espacio: espacio,

                              procesando: procesando,

                              onConfigurar: () {
                                configurarEspacio(espacio);
                              },

                              onCambiarEstado: () {
                                cambiarEstado(espacio);
                              },
                            ),
                          );
                        },
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

// =================================================================
// RESUMEN
// =================================================================

class _ResumenEspacios extends StatelessWidget {
  final int activos;
  final int pendientesGps;
  final int pendientesNfc;

  const _ResumenEspacios({
    required this.activos,
    required this.pendientesGps,
    required this.pendientesNfc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),

        borderRadius: BorderRadius.circular(12),
      ),

      child: Wrap(
        spacing: 22,
        runSpacing: 10,

        children: [
          _DatoResumen(
            icono: Icons.meeting_room_outlined,

            texto: '$activos activos',
          ),

          _DatoResumen(
            icono: Icons.location_on_outlined,

            texto: '$pendientesGps sin GPS',
          ),

          _DatoResumen(
            icono: Icons.nfc_outlined,

            texto: '$pendientesNfc sin NFC',
          ),
        ],
      ),
    );
  }
}

class _DatoResumen extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _DatoResumen({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,

      children: [
        Icon(icono, size: 19, color: const Color(0xFF1565C0)),

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
// TARJETA ESPACIO
// =================================================================

class _TarjetaEspacio extends StatelessWidget {
  final Map<String, dynamic> espacio;

  final VoidCallback onConfigurar;
  final VoidCallback onCambiarEstado;

  final bool procesando;

  const _TarjetaEspacio({
    required this.espacio,
    required this.onConfigurar,
    required this.onCambiarEstado,
    required this.procesando,
  });

  @override
  Widget build(BuildContext context) {
    final bool activo = espacio['activo'] == true;

    final bool gps = espacio['gpsConfigurado'] == true;

    final bool nfc = espacio['nfcConfigurado'] == true;

    final bool configuracionCompleta = gps && nfc;

    final String codigo = (espacio['codigo'] ?? '').toString().trim();

    final String nombre = (espacio['nombreVisible'] ?? '').toString().trim();

    final String edificio = (espacio['edificioCodigo'] ?? '-').toString();

    final String piso = (espacio['pisoNumero'] ?? '-').toString();

    final String tipo = (espacio['tipo'] ?? 'Sin tipo').toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(
          color: configuracionCompleta
              ? const Color(0xFFD1FAE5)
              : const Color(0xFFE5E7EB),
        ),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // =======================================================
          // CABECERA: CÓDIGO + ESTADO
          // =======================================================

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              // ---------------------------------------------------
              // CÓDIGO
              // ---------------------------------------------------

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),

                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(10),
                ),

                child: Text(
                  codigo.isEmpty ? 'Sin código' : codigo,

                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF7C3AED),
                  ),
                ),
              ),

              const Spacer(),

              // ---------------------------------------------------
              // ACTIVO / INACTIVO
              // ---------------------------------------------------
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
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
                      activo ? Icons.check_circle : Icons.block,

                      size: 15,

                      color: activo
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF6B7280),
                    ),

                    const SizedBox(width: 5),

                    Text(
                      activo ? 'ACTIVO' : 'INACTIVO',

                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,

                        color: activo
                            ? const Color(0xFF15803D)
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // =======================================================
          // NOMBRE
          // =======================================================
          Text(
            nombre.isEmpty ? codigo : nombre,

            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),

          const SizedBox(height: 10),

          // =======================================================
          // UBICACIÓN / TIPO
          // =======================================================
          Wrap(
            spacing: 8,
            runSpacing: 8,

            children: [
              _DatoEspacioChip(
                icono: Icons.apartment_outlined,
                texto: 'Edificio $edificio',
              ),

              _DatoEspacioChip(
                icono: Icons.layers_outlined,
                texto: 'Piso $piso',
              ),

              _DatoEspacioChip(icono: Icons.category_outlined, texto: tipo),
            ],
          ),

          const SizedBox(height: 16),

          const Divider(height: 1),

          const SizedBox(height: 16),

          // =======================================================
          // CONFIGURACIÓN
          // =======================================================
          const Text(
            'Configuración del espacio',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4B5563),
            ),
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,

            children: [
              _EstadoPequeno(
                texto: gps ? 'GPS configurado' : 'GPS pendiente',

                correcto: gps,

                icono: Icons.location_on_outlined,
              ),

              _EstadoPequeno(
                texto: nfc ? 'NFC configurado' : 'NFC pendiente',

                correcto: nfc,

                icono: Icons.nfc_outlined,
              ),
            ],
          ),

          const SizedBox(height: 18),

          // =======================================================
          // BOTÓN PRINCIPAL
          // =======================================================
          SizedBox(
            width: double.infinity,
            height: 48,

            child: ElevatedButton.icon(
              onPressed: procesando ? null : onConfigurar,

              icon: procesando
                  ? const SizedBox(
                      width: 18,
                      height: 18,

                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      configuracionCompleta
                          ? Icons.settings_outlined
                          : Icons.add_location_alt_outlined,
                    ),

              label: Text(
                procesando
                    ? 'Procesando...'
                    : configuracionCompleta
                    ? 'Revisar / actualizar GPS y NFC'
                    : 'Configurar ubicación y NFC',

                style: const TextStyle(fontWeight: FontWeight.w600),
              ),

              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),

                foregroundColor: Colors.white,

                disabledBackgroundColor: const Color(0xFF93C5FD),

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // =======================================================
          // ACTIVAR / DESACTIVAR
          // =======================================================
          SizedBox(
            width: double.infinity,

            child: TextButton.icon(
              onPressed: procesando ? null : onCambiarEstado,

              icon: Icon(
                activo
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,

                size: 19,
              ),

              label: Text(activo ? 'Desactivar espacio' : 'Activar espacio'),

              style: TextButton.styleFrom(
                foregroundColor: activo
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF16A34A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// CHIP DE INFORMACIÓN DEL ESPACIO
// =================================================================

class _DatoEspacioChip extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _DatoEspacioChip({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),

      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),

        borderRadius: BorderRadius.circular(9),

        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(icono, size: 15, color: const Color(0xFF6B7280)),

          const SizedBox(width: 5),

          Text(
            texto,
            style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// ESTADO PEQUEÑO
// =================================================================

class _EstadoPequeno extends StatelessWidget {
  final String texto;
  final bool correcto;
  final IconData icono;

  const _EstadoPequeno({
    required this.texto,
    required this.correcto,
    required this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),

      decoration: BoxDecoration(
        color: correcto ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7ED),

        borderRadius: BorderRadius.circular(20),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(
            icono,

            size: 15,

            color: correcto ? const Color(0xFF16A34A) : const Color(0xFFEA580C),
          ),

          const SizedBox(width: 5),

          Text(
            texto,

            style: TextStyle(
              fontSize: 11,

              fontWeight: FontWeight.w600,

              color: correcto
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFEA580C),
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// FILTRO
// =================================================================

class _FiltroEstado extends StatelessWidget {
  final String texto;
  final bool seleccionado;
  final VoidCallback onTap;

  const _FiltroEstado({
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
          color: seleccionado ? const Color(0xFF7C3AED) : Colors.white,

          borderRadius: BorderRadius.circular(20),

          border: Border.all(
            color: seleccionado
                ? const Color(0xFF7C3AED)
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

class _ErrorEspacios extends StatelessWidget {
  final String mensaje;

  final Future<void> Function() onReintentar;

  const _ErrorEspacios({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
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
// SIN ESPACIOS
// =================================================================

class _SinEspacios extends StatelessWidget {
  const _SinEspacios();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Icon(
              Icons.meeting_room_outlined,

              size: 58,

              color: Color(0xFF9CA3AF),
            ),

            SizedBox(height: 14),

            Text(
              'No se encontraron espacios',

              style: TextStyle(
                fontSize: 18,

                fontWeight: FontWeight.bold,

                color: Color(0xFF1F2937),
              ),
            ),

            SizedBox(height: 6),

            Text(
              'Puedes crear los espacios desde la estructura de un edificio o modificar los filtros.',

              textAlign: TextAlign.center,

              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
