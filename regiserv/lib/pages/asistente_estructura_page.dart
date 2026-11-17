import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AsistenteEstructuraPage extends StatefulWidget {
  const AsistenteEstructuraPage({super.key});

  @override
  State<AsistenteEstructuraPage> createState() =>
      _AsistenteEstructuraPageState();
}

class _AsistenteEstructuraPageState extends State<AsistenteEstructuraPage> {
  final formKey = GlobalKey<FormState>();

  final nombreController = TextEditingController();

  final codigoController = TextEditingController();

  SupabaseClient get supabase => Supabase.instance.client;

  int cantidadPisos = 1;

  bool cargandoDatos = true;
  bool guardando = false;

  String? errorCarga;

  List<String> tiposActivos = [];

  final Set<String> codigosEdificiosExistentes = {};

  // =============================================================
  // BLOQUES TEMPORALES
  // =============================================================

  final Map<int, List<_BloqueEspacios>> bloquesPorPiso = {1: []};

  // =============================================================
  // INICIALIZACIÓN
  // =============================================================

  @override
  void initState() {
    super.initState();

    cargarDatosIniciales();
  }

  @override
  void dispose() {
    nombreController.dispose();
    codigoController.dispose();

    super.dispose();
  }

  // =============================================================
  // CARGAR TIPOS Y CÓDIGOS EXISTENTES
  // =============================================================

  Future<void> cargarDatosIniciales() async {
    if (mounted) {
      setState(() {
        cargandoDatos = true;
        errorCarga = null;
      });
    }

    try {
      final tiposData = await supabase
          .from('tipo_espacio')
          .select('nombre, activo')
          .eq('activo', true)
          .order('nombre');

      final edificiosData = await supabase.from('edificio').select('codigo');

      final nuevosTipos = <String>[];

      for (final tipo in tiposData) {
        final nombre = (tipo['nombre'] ?? '').toString().trim();

        if (nombre.isNotEmpty) {
          nuevosTipos.add(nombre);
        }
      }

      final nuevosCodigos = <String>{};

      for (final edificio in edificiosData) {
        final codigo = (edificio['codigo'] ?? '')
            .toString()
            .trim()
            .toUpperCase();

        if (codigo.isNotEmpty) {
          nuevosCodigos.add(codigo);
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        tiposActivos = nuevosTipos;

        codigosEdificiosExistentes
          ..clear()
          ..addAll(nuevosCodigos);

        cargandoDatos = false;
      });
    } catch (error) {
      debugPrint('ERROR CARGANDO DATOS ESTRUCTURA: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        cargandoDatos = false;

        errorCarga =
            'No fue posible cargar los datos necesarios desde Supabase.';
      });
    }
  }

  // =============================================================
  // CAMBIAR CANTIDAD DE PISOS
  // =============================================================

  void actualizarCantidadPisos(int nuevaCantidad) {
    setState(() {
      cantidadPisos = nuevaCantidad;

      for (int piso = 1; piso <= cantidadPisos; piso++) {
        bloquesPorPiso.putIfAbsent(piso, () => []);
      }

      bloquesPorPiso.removeWhere((piso, _) => piso > cantidadPisos);
    });
  }

  // =============================================================
  // AGREGAR BLOQUE
  // =============================================================

  Future<void> agregarBloque(int piso) async {
    if (tiposActivos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No existen tipos de espacio activos.')),
      );

      return;
    }

    final resultado = await showDialog<_BloqueEspacios>(
      context: context,
      barrierDismissible: false,

      builder: (context) {
        return _AgregarBloqueDialog(
          tipos: tiposActivos,

          piso: piso,

          bloquesExistentes: bloquesPorPiso[piso] ?? [],
        );
      },
    );

    if (resultado == null || !mounted) {
      return;
    }

    setState(() {
      bloquesPorPiso[piso]!.add(resultado);
    });
  }

  // =============================================================
  // ELIMINAR BLOQUE
  // =============================================================

  void eliminarBloque(int piso, int indice) {
    setState(() {
      bloquesPorPiso[piso]!.removeAt(indice);
    });
  }

  // =============================================================
  // CÓDIGO DE ESPACIO
  // =============================================================

  String codigoEspacio(int piso, int numero) {
    final codigoEdificio = codigoController.text.trim().toUpperCase();

    final numeroTexto = numero.toString().padLeft(2, '0');

    return '$codigoEdificio$piso$numeroTexto';
  }

  // =============================================================
  // TOTAL ESPACIOS
  // =============================================================

  int get totalEspacios {
    int total = 0;

    for (final bloques in bloquesPorPiso.values) {
      for (final bloque in bloques) {
        total += bloque.cantidad;
      }
    }

    return total;
  }

  // =============================================================
  // CÓDIGO EDIFICIO DUPLICADO
  // =============================================================

  bool codigoEdificioExiste(String codigo) {
    return codigosEdificiosExistentes.contains(codigo.trim().toUpperCase());
  }

  // =============================================================
  // CONSTRUIR JSON DE ESPACIOS
  // =============================================================

  List<Map<String, dynamic>> construirEspacios() {
    final resultado = <Map<String, dynamic>>[];

    for (int piso = 1; piso <= cantidadPisos; piso++) {
      final bloques = bloquesPorPiso[piso] ?? [];

      for (final bloque in bloques) {
        if (bloque.sinNumeracion) {
          for (int indice = 0; indice < bloque.cantidad; indice++) {
            resultado.add({
              'piso': piso,
              'tipo': bloque.tipo,
              'numero': null,
              'sin_numeracion': true,
            });
          }
        } else {
          for (int numero = bloque.desde; numero <= bloque.hasta; numero++) {
            resultado.add({
              'piso': piso,
              'tipo': bloque.tipo,
              'numero': numero,
            });
          }
        }
      }
    }

    return resultado;
  }

  // =============================================================
  // CREAR ESTRUCTURA REAL
  // =============================================================

  Future<void> crearEstructura() async {
    if (guardando) {
      return;
    }

    if (!formKey.currentState!.validate()) {
      return;
    }

    // -----------------------------------------------------------
    // CONFIRMACIÓN
    // -----------------------------------------------------------

    bool continuar = false;

    if (totalEspacios == 0) {
      continuar =
          await showDialog<bool>(
            context: context,

            builder: (context) {
              return AlertDialog(
                title: const Text('Sin espacios configurados'),

                content: const Text(
                  'Todavía no has agregado espacios a ningún piso. '
                  'Puedes crear solamente el edificio y sus pisos y completar los espacios después. '
                  '¿Deseas continuar?',
                ),

                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context, false);
                    },

                    child: const Text('Volver'),
                  ),

                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context, true);
                    },

                    child: const Text('Crear igualmente'),
                  ),
                ],
              );
            },
          ) ??
          false;
    } else {
      continuar =
          await showDialog<bool>(
            context: context,

            builder: (context) {
              return AlertDialog(
                title: const Text('Crear estructura'),

                content: Text(
                  'Se creará ${nombreController.text.trim()}, '
                  '$cantidadPisos ${cantidadPisos == 1 ? 'piso' : 'pisos'} '
                  'y $totalEspacios ${totalEspacios == 1 ? 'espacio' : 'espacios'}. '
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

                    child: const Text('Crear'),
                  ),
                ],
              );
            },
          ) ??
          false;
    }

    if (!continuar || !mounted) {
      return;
    }

    setState(() {
      guardando = true;
    });

    try {
      // =========================================================
      // RPC POSTGRESQL
      // =========================================================

      final respuesta = await supabase.rpc(
        'crear_estructura',

        params: {
          'p_nombre': nombreController.text.trim(),

          'p_codigo': codigoController.text.trim().toUpperCase(),

          'p_cantidad_pisos': cantidadPisos,

          'p_espacios': construirEspacios(),
        },
      );

      debugPrint('RESPUESTA CREAR ESTRUCTURA: $respuesta');

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

                Text('Estructura creada'),
              ],
            ),

            content: Text(
              '${nombreController.text.trim()} fue creado correctamente con '
              '$cantidadPisos ${cantidadPisos == 1 ? 'piso' : 'pisos'} '
              'y $totalEspacios ${totalEspacios == 1 ? 'espacio' : 'espacios'}.',
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
        'ERROR RPC CREAR ESTRUCTURA: '
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
    } catch (error) {
      debugPrint('ERROR CREAR ESTRUCTURA: $error');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible crear la estructura.'),

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
    if (cargandoDatos) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),

        appBar: AppBar(
          backgroundColor: Colors.white,

          title: const Text('Nueva estructura'),
        ),

        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (errorCarga != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),

        appBar: AppBar(
          backgroundColor: Colors.white,

          title: const Text('Nueva estructura'),
        ),

        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30),

            child: Column(
              mainAxisSize: MainAxisSize.min,

              children: [
                const Icon(
                  Icons.cloud_off_outlined,

                  size: 56,

                  color: Color(0xFF9CA3AF),
                ),

                const SizedBox(height: 14),

                Text(errorCarga!, textAlign: TextAlign.center),

                const SizedBox(height: 18),

                ElevatedButton.icon(
                  onPressed: cargarDatosIniciales,

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
          'Nueva estructura',

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

              child: Form(
                key: formKey,

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    const Text(
                      'Crear edificio y espacios',

                      style: TextStyle(
                        fontSize: 26,

                        fontWeight: FontWeight.bold,

                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Define el edificio una sola vez y luego agrega los espacios de cada piso en grupos.',

                      style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
                    ),

                    const SizedBox(height: 26),

                    // ============================================
                    // PASO 1
                    // ============================================
                    const _TituloPaso(numero: 1, titulo: 'Datos del edificio'),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: nombreController,

                      enabled: !guardando,

                      textCapitalization: TextCapitalization.words,

                      decoration: _decoracionCampo(
                        etiqueta: 'Nombre del edificio *',

                        icono: Icons.apartment_outlined,

                        ayuda: 'Ej.: Edificio P',
                      ),

                      validator: (valor) {
                        if (valor == null || valor.trim().isEmpty) {
                          return 'Ingresa el nombre del edificio.';
                        }

                        return null;
                      },

                      onChanged: (_) {
                        setState(() {});
                      },
                    ),

                    const SizedBox(height: 14),

                    TextFormField(
                      controller: codigoController,

                      enabled: !guardando,

                      textCapitalization: TextCapitalization.characters,

                      decoration: _decoracionCampo(
                        etiqueta: 'Código *',

                        icono: Icons.tag_outlined,

                        ayuda: 'Ej.: P',
                      ),

                      validator: (valor) {
                        if (valor == null || valor.trim().isEmpty) {
                          return 'Ingresa el código del edificio.';
                        }

                        if (codigoEdificioExiste(valor)) {
                          return 'Ya existe un edificio con este código.';
                        }

                        return null;
                      },

                      onChanged: (_) {
                        setState(() {});
                      },
                    ),

                    const SizedBox(height: 14),

                    DropdownButtonFormField<int>(
                      value: cantidadPisos,

                      decoration: _decoracionCampo(
                        etiqueta: 'Cantidad de pisos *',

                        icono: Icons.layers_outlined,
                      ),

                      items: List.generate(20, (index) {
                        final cantidad = index + 1;

                        return DropdownMenuItem<int>(
                          value: cantidad,

                          child: Text(
                            cantidad == 1 ? '1 piso' : '$cantidad pisos',
                          ),
                        );
                      }),

                      onChanged: guardando
                          ? null
                          : (valor) {
                              if (valor != null) {
                                actualizarCantidadPisos(valor);
                              }
                            },
                    ),

                    const SizedBox(height: 30),

                    // ============================================
                    // PASO 2
                    // ============================================
                    const _TituloPaso(numero: 2, titulo: 'Espacios por piso'),

                    const SizedBox(height: 6),

                    const Text(
                      'Agrega grupos de espacios. Por ejemplo: Laboratorio 01 al 05 o Sala 06 al 10.',

                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),

                    const SizedBox(height: 18),

                    for (int piso = 1; piso <= cantidadPisos; piso++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),

                        child: _TarjetaPisoConfiguracion(
                          piso: piso,

                          bloques: bloquesPorPiso[piso] ?? [],

                          codigoEspacio: codigoEspacio,

                          onAgregar: () {
                            agregarBloque(piso);
                          },

                          onEliminar: (indice) {
                            eliminarBloque(piso, indice);
                          },
                        ),
                      ),

                    const SizedBox(height: 10),

                    // ============================================
                    // RESUMEN
                    // ============================================
                    Container(
                      width: double.infinity,

                      padding: const EdgeInsets.all(18),

                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),

                        borderRadius: BorderRadius.circular(14),
                      ),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          const Text(
                            'Resumen',

                            style: TextStyle(
                              fontSize: 17,

                              fontWeight: FontWeight.bold,

                              color: Color(0xFF1E40AF),
                            ),
                          ),

                          const SizedBox(height: 10),

                          Text(
                            'Edificio: '
                            '${nombreController.text.trim().isEmpty ? 'Sin definir' : nombreController.text.trim()}',
                          ),

                          Text('Pisos: $cantidadPisos'),

                          Text('Espacios a crear: $totalEspacios'),

                          const SizedBox(height: 10),

                          const Text(
                            'El GPS y NFC se asociarán posteriormente a cada espacio físico.',

                            style: TextStyle(
                              fontSize: 13,

                              color: Color(0xFF1E40AF),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ============================================
                    // CREAR
                    // ============================================
                    SizedBox(
                      width: double.infinity,

                      height: 54,

                      child: ElevatedButton(
                        onPressed: guardando ? null : crearEstructura,

                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),

                          foregroundColor: Colors.white,
                        ),

                        child: guardando
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,

                                children: [
                                  SizedBox(
                                    width: 20,

                                    height: 20,

                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,

                                      color: Colors.white,
                                    ),
                                  ),

                                  SizedBox(width: 12),

                                  Text('Creando estructura...'),
                                ],
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,

                                children: [
                                  Icon(Icons.account_tree_outlined),

                                  SizedBox(width: 8),

                                  Text(
                                    'Crear edificio y estructura',

                                    style: TextStyle(
                                      fontSize: 16,

                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
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

  // =============================================================
  // DECORACIÓN
  // =============================================================

  InputDecoration _decoracionCampo({
    required String etiqueta,
    required IconData icono,
    String? ayuda,
  }) {
    return InputDecoration(
      labelText: etiqueta,

      helperText: ayuda,

      prefixIcon: Icon(icono),

      filled: true,

      fillColor: Colors.white,

      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

// =================================================================
// BLOQUE
// =================================================================

class _BloqueEspacios {
  final String tipo;
  final int desde;
  final int hasta;
  final bool sinNumeracion;
  final int cantidadSinNumero;

  const _BloqueEspacios({
    required this.tipo,
    required this.desde,
    required this.hasta,
    this.sinNumeracion = false,
    this.cantidadSinNumero = 1,
  });

  int get cantidad => sinNumeracion ? cantidadSinNumero : hasta - desde + 1;
}

// =================================================================
// AGREGAR BLOQUE
// =================================================================

class _AgregarBloqueDialog extends StatefulWidget {
  final List<String> tipos;
  final int piso;

  final List<_BloqueEspacios> bloquesExistentes;

  const _AgregarBloqueDialog({
    required this.tipos,
    required this.piso,
    required this.bloquesExistentes,
  });

  @override
  State<_AgregarBloqueDialog> createState() => _AgregarBloqueDialogState();
}

class _AgregarBloqueDialogState extends State<_AgregarBloqueDialog> {
  final formKey = GlobalKey<FormState>();

  final desdeController = TextEditingController();

  final hastaController = TextEditingController();
  final cantidadController = TextEditingController(text: '1');

  String? tipoSeleccionado;
  bool sinNumeracion = false;

  @override
  void dispose() {
    desdeController.dispose();
    hastaController.dispose();
    cantidadController.dispose();

    super.dispose();
  }

  bool rangoYaUtilizado(int desde, int hasta) {
    return widget.bloquesExistentes.any(
      (bloque) =>
          !bloque.sinNumeracion &&
          desde <= bloque.hasta &&
          hasta >= bloque.desde,
    );
  }

  String? validarNumero(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Obligatorio.';
    }

    final numero = int.tryParse(valor.trim());

    if (numero == null || numero < 1 || numero > 99) {
      return 'Usa 1 a 99.';
    }

    return null;
  }

  void guardar() {
    if (!formKey.currentState!.validate()) {
      return;
    }

    if (sinNumeracion) {
      Navigator.pop(
        context,
        _BloqueEspacios(
          tipo: tipoSeleccionado!,
          desde: 0,
          hasta: 0,
          sinNumeracion: true,
          cantidadSinNumero: int.parse(cantidadController.text.trim()),
        ),
      );
      return;
    }

    final desde = int.parse(desdeController.text.trim());
    final hasta = int.parse(hastaController.text.trim());
    Navigator.pop(
      context,
      _BloqueEspacios(tipo: tipoSeleccionado!, desde: desde, hasta: hasta),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Agregar espacios · Piso ${widget.piso}'),

      content: SizedBox(
        width: 440,

        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                const Text(
                  'Selecciona el tipo y elige si los espacios tendrán número o solo el nombre (ej.: Baño, Biblioteca).',

                  style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
                ),

                const SizedBox(height: 18),

                DropdownButtonFormField<String>(
                  value: tipoSeleccionado,

                  decoration: const InputDecoration(
                    labelText: 'Tipo de espacio *',

                    prefixIcon: Icon(Icons.category_outlined),

                    border: OutlineInputBorder(),
                  ),

                  items: widget.tipos.map((tipo) {
                    return DropdownMenuItem<String>(
                      value: tipo,

                      child: Text(tipo),
                    );
                  }).toList(),

                  onChanged: (valor) {
                    setState(() {
                      tipoSeleccionado = valor;
                    });
                  },

                  validator: (valor) {
                    if (valor == null) {
                      return 'Selecciona un tipo de espacio.';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sin numeración'),
                  subtitle: const Text(
                    'El nombre será solo el tipo: Baño, Biblioteca, etc.',
                  ),
                  value: sinNumeracion,
                  onChanged: (valor) => setState(() {
                    sinNumeracion = valor;
                  }),
                ),
                const SizedBox(height: 12),
                if (sinNumeracion)
                  TextFormField(
                    controller: cantidadController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad de espacios (1 a 99)',
                      hintText: '1',
                      border: OutlineInputBorder(),
                    ),
                    validator: (valor) {
                      final n = int.tryParse((valor ?? '').trim());
                      if (n == null || n < 1 || n > 99) {
                        return 'Ingresa una cantidad entre 1 y 99.';
                      }
                      return null;
                    },
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: desdeController,

                          keyboardType: TextInputType.number,

                          decoration: const InputDecoration(
                            labelText: 'Desde *',

                            hintText: '01',

                            border: OutlineInputBorder(),
                          ),

                          validator: (valor) {
                            final error = validarNumero(valor);

                            if (error != null) {
                              return error;
                            }

                            final desde = int.tryParse(valor!.trim());

                            final hasta = int.tryParse(
                              hastaController.text.trim(),
                            );

                            if (desde == null ||
                                hasta == null ||
                                hasta < desde) {
                              return null;
                            }

                            if (rangoYaUtilizado(desde, hasta)) {
                              return 'Combinación ya utilizada.';
                            }

                            return null;
                          },

                          onChanged: (_) {
                            formKey.currentState?.validate();
                          },
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: TextFormField(
                          controller: hastaController,

                          keyboardType: TextInputType.number,

                          decoration: const InputDecoration(
                            labelText: 'Hasta *',

                            hintText: '05',

                            border: OutlineInputBorder(),
                          ),

                          validator: (valor) {
                            final error = validarNumero(valor);

                            if (error != null) {
                              return error;
                            }

                            final desde = int.tryParse(
                              desdeController.text.trim(),
                            );

                            final hasta = int.tryParse(valor!.trim());

                            if (desde == null || hasta == null) {
                              return null;
                            }

                            if (hasta < desde) {
                              return 'Debe ser mayor o igual.';
                            }

                            if (rangoYaUtilizado(desde, hasta)) {
                              return 'Combinación ya utilizada.';
                            }

                            return null;
                          },

                          onChanged: (_) {
                            formKey.currentState?.validate();
                          },
                        ),
                      ),
                    ],
                  ),

                if (!sinNumeracion && widget.bloquesExistentes.isNotEmpty) ...[
                  const SizedBox(height: 14),

                  Container(
                    width: double.infinity,

                    padding: const EdgeInsets.all(12),

                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),

                      borderRadius: BorderRadius.circular(10),
                    ),

                    child: const Text(
                      'Los números de espacio deben ser únicos dentro del mismo piso.',

                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                  ),
                ],
              ],
            ),
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

          icon: const Icon(Icons.add_outlined),

          label: const Text('Agregar'),
        ),
      ],
    );
  }
}

// =================================================================
// TÍTULO
// =================================================================

class _TituloPaso extends StatelessWidget {
  final int numero;
  final String titulo;

  const _TituloPaso({required this.numero, required this.titulo});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 17,

          backgroundColor: const Color(0xFF1565C0),

          foregroundColor: Colors.white,

          child: Text(numero.toString()),
        ),

        const SizedBox(width: 10),

        Text(
          titulo,

          style: const TextStyle(
            fontSize: 20,

            fontWeight: FontWeight.bold,

            color: Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }
}

// =================================================================
// TARJETA PISO
// =================================================================

class _TarjetaPisoConfiguracion extends StatelessWidget {
  final int piso;

  final List<_BloqueEspacios> bloques;

  final String Function(int piso, int numero) codigoEspacio;

  final VoidCallback onAgregar;

  final void Function(int indice) onEliminar;

  const _TarjetaPisoConfiguracion({
    required this.piso,
    required this.bloques,
    required this.codigoEspacio,
    required this.onAgregar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final cantidad = bloques.fold<int>(
      0,
      (total, bloque) => total + bloque.cantidad,
    );

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Container(
                width: 44,

                height: 44,

                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDFA),

                  borderRadius: BorderRadius.circular(10),
                ),

                child: const Icon(
                  Icons.layers_outlined,

                  color: Color(0xFF0F766E),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      'Piso $piso',

                      style: const TextStyle(
                        fontSize: 17,

                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    Text(
                      '$cantidad ${cantidad == 1 ? 'espacio configurado' : 'espacios configurados'}',

                      style: const TextStyle(
                        fontSize: 13,

                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),

              OutlinedButton.icon(
                onPressed: onAgregar,

                icon: const Icon(Icons.add),

                label: const Text('Agregar espacios'),
              ),
            ],
          ),

          if (bloques.isNotEmpty) ...[
            const SizedBox(height: 16),

            const Divider(),

            for (int i = 0; i < bloques.length; i++)
              _FilaBloque(
                piso: piso,

                bloque: bloques[i],

                codigoEspacio: codigoEspacio,

                onEliminar: () {
                  onEliminar(i);
                },
              ),
          ],
        ],
      ),
    );
  }
}

// =================================================================
// FILA BLOQUE
// =================================================================

class _FilaBloque extends StatelessWidget {
  final int piso;

  final _BloqueEspacios bloque;

  final String Function(int piso, int numero) codigoEspacio;

  final VoidCallback onEliminar;

  const _FilaBloque({
    required this.piso,
    required this.bloque,
    required this.codigoEspacio,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final rango = bloque.sinNumeracion
        ? 'Sin número'
        : (bloque.desde == bloque.hasta
              ? codigoEspacio(piso, bloque.desde)
              : '${codigoEspacio(piso, bloque.desde)} – '
                    '${codigoEspacio(piso, bloque.hasta)}');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),

      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  bloque.tipo,

                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),

                const SizedBox(height: 2),

                Text(
                  '$rango · ${bloque.cantidad} ${bloque.cantidad == 1 ? 'espacio' : 'espacios'}',

                  style: const TextStyle(
                    fontSize: 13,

                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            tooltip: 'Quitar bloque',

            onPressed: onEliminar,

            icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
          ),
        ],
      ),
    );
  }
}
