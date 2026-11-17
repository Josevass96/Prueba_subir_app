import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/sesion_data.dart';
import 'iniciar_labor_page.dart';

class LaboresDisponiblesPage extends StatefulWidget {
  const LaboresDisponiblesPage({super.key});

  @override
  State<LaboresDisponiblesPage> createState() => _LaboresDisponiblesPageState();
}

class _LaboresDisponiblesPageState extends State<LaboresDisponiblesPage> {
  SupabaseClient get supabase => Supabase.instance.client;

  List<Map<String, dynamic>> labores = [];

  bool cargando = true;
  String? mensajeError;

  @override
  void initState() {
    super.initState();

    cargarLabores();
  }

  // =============================================================
  // CONVERSIÓN SEGURA A INT
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
  // CARGAR LABORES DEL AUXILIAR
  // =============================================================

  Future<void> cargarLabores() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;
      });
    }

    try {
      // ---------------------------------------------------------
      // USUARIO AUTENTICADO
      // ---------------------------------------------------------

      final usuarioAuth = supabase.auth.currentUser;

      if (usuarioAuth == null) {
        throw Exception('No existe una sesión autenticada en Supabase.');
      }

      final idUsuario = usuarioAuth.id;

      // ---------------------------------------------------------
      // ESPACIOS ASIGNADOS VIGENTES
      // ---------------------------------------------------------

      final asignacionesData = await supabase
          .from('espacio_trabajador')
          .select(
            'id_espacio, '
            'fecha_ini, '
            'comentario',
          )
          .eq('id_usuario', idUsuario)
          .isFilter('fecha_ter', null);

      final List<Map<String, dynamic>> asignaciones = [];

      for (final fila in asignacionesData) {
        asignaciones.add(Map<String, dynamic>.from(fila));
      }

      // ---------------------------------------------------------
      // SI NO TIENE ASIGNACIONES
      // ---------------------------------------------------------

      if (asignaciones.isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          labores = [];
          cargando = false;
        });

        return;
      }

      // ---------------------------------------------------------
      // IDS DE ESPACIOS
      // ---------------------------------------------------------

      final List<int> idsEspacios = [];

      for (final asignacion in asignaciones) {
        final id = aInt(asignacion['id_espacio']);

        if (id != null) {
          idsEspacios.add(id);
        }
      }

      // ---------------------------------------------------------
      // DATOS DE LOS ESPACIOS
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
          )
          .inFilter('id_espacio', idsEspacios);

      final Map<int, Map<String, dynamic>> espaciosPorId = {};

      for (final fila in espaciosData) {
        final espacio = Map<String, dynamic>.from(fila);

        final idEspacio = aInt(espacio['id_espacio']);

        if (idEspacio == null) {
          continue;
        }

        espaciosPorId[idEspacio] = espacio;
      }

      // ---------------------------------------------------------
      // IDS DE PISOS
      // ---------------------------------------------------------

      final Set<int> idsPisos = {};

      for (final espacio in espaciosPorId.values) {
        final idPiso = aInt(espacio['id_piso']);

        if (idPiso != null) {
          idsPisos.add(idPiso);
        }
      }

      // ---------------------------------------------------------
      // PISOS
      // ---------------------------------------------------------

      final Map<int, Map<String, dynamic>> pisosPorId = {};

      if (idsPisos.isNotEmpty) {
        final pisosData = await supabase
            .from('piso_nivel')
            .select(
              'id_piso, '
              'id_edificio, '
              'numero_nivel, '
              'activo',
            )
            .inFilter('id_piso', idsPisos.toList());

        for (final fila in pisosData) {
          final piso = Map<String, dynamic>.from(fila);

          final idPiso = aInt(piso['id_piso']);

          if (idPiso == null) {
            continue;
          }

          pisosPorId[idPiso] = piso;
        }
      }

      // ---------------------------------------------------------
      // IDS DE EDIFICIOS
      // ---------------------------------------------------------

      final Set<int> idsEdificios = {};

      for (final piso in pisosPorId.values) {
        final idEdificio = aInt(piso['id_edificio']);

        if (idEdificio != null) {
          idsEdificios.add(idEdificio);
        }
      }

      // ---------------------------------------------------------
      // EDIFICIOS
      // ---------------------------------------------------------

      final Map<int, Map<String, dynamic>> edificiosPorId = {};

      if (idsEdificios.isNotEmpty) {
        final edificiosData = await supabase
            .from('edificio')
            .select(
              'id_edificio, '
              'codigo, '
              'nombre, '
              'activo',
            )
            .inFilter('id_edificio', idsEdificios.toList());

        for (final fila in edificiosData) {
          final edificio = Map<String, dynamic>.from(fila);

          final idEdificio = aInt(edificio['id_edificio']);

          if (idEdificio == null) {
            continue;
          }

          edificiosPorId[idEdificio] = edificio;
        }
      }

      // ---------------------------------------------------------
      // IDS DE TIPOS DE ESPACIO
      // ---------------------------------------------------------

      final Set<int> idsTipos = {};

      for (final espacio in espaciosPorId.values) {
        final idTipo = aInt(espacio['id_tipo_espacio']);

        if (idTipo != null) {
          idsTipos.add(idTipo);
        }
      }

      // ---------------------------------------------------------
      // TIPOS DE ESPACIO
      // ---------------------------------------------------------

      final Map<int, Map<String, dynamic>> tiposPorId = {};

      if (idsTipos.isNotEmpty) {
        final tiposData = await supabase
            .from('tipo_espacio')
            .select(
              'id_tipo_espacio, '
              'nombre',
            )
            .inFilter('id_tipo_espacio', idsTipos.toList());

        for (final fila in tiposData) {
          final tipo = Map<String, dynamic>.from(fila);

          final idTipo = aInt(tipo['id_tipo_espacio']);

          if (idTipo == null) {
            continue;
          }

          tiposPorId[idTipo] = tipo;
        }
      }

      // ---------------------------------------------------------
      // ESTADOS NFC OPERATIVOS
      // ---------------------------------------------------------

      final estadosNfcData = await supabase
          .from('estado_nfc')
          .select(
            'id_estado_nfc, '
            'activo',
          );

      final Set<int> estadosNfcOperativos = {};

      for (final fila in estadosNfcData) {
        if (fila['activo'] != true) {
          continue;
        }

        final idEstado = aInt(fila['id_estado_nfc']);

        if (idEstado != null) {
          estadosNfcOperativos.add(idEstado);
        }
      }

      // ---------------------------------------------------------
      // NFC ACTIVAS DE LOS ESPACIOS
      // ---------------------------------------------------------

      final Map<int, Map<String, dynamic>> nfcPorEspacio = {};

      final nfcData = await supabase
          .from('nfc')
          .select(
            'id_nfc, '
            'id_espacio, '
            'id_estado_nfc, '
            'uid_nfc, '
            'fecha_instalacion, '
            'fecha_retiro',
          )
          .inFilter('id_espacio', idsEspacios)
          .isFilter('fecha_retiro', null);

      for (final fila in nfcData) {
        final nfc = Map<String, dynamic>.from(fila);

        final idEspacio = aInt(nfc['id_espacio']);

        final idEstado = aInt(nfc['id_estado_nfc']);

        if (idEspacio == null || idEstado == null) {
          continue;
        }

        if (!estadosNfcOperativos.contains(idEstado)) {
          continue;
        }

        // Si por alguna inconsistencia hubiera más de una,
        // conservamos la primera vigente encontrada.
        nfcPorEspacio.putIfAbsent(idEspacio, () => nfc);
      }

      // ---------------------------------------------------------
      // ARMAR LABORES
      // ---------------------------------------------------------

      final List<Map<String, dynamic>> laboresTemporales = [];

      for (final asignacion in asignaciones) {
        final idEspacio = aInt(asignacion['id_espacio']);

        if (idEspacio == null) {
          continue;
        }

        final espacio = espaciosPorId[idEspacio];

        if (espacio == null) {
          continue;
        }

        // No mostrar espacios inactivos.
        if (espacio['activo'] != true) {
          continue;
        }

        final idPiso = aInt(espacio['id_piso']);

        final piso = idPiso == null ? null : pisosPorId[idPiso];

        if (piso == null || piso['activo'] != true) {
          continue;
        }

        final idEdificio = aInt(piso['id_edificio']);

        final edificio = idEdificio == null ? null : edificiosPorId[idEdificio];

        if (edificio == null || edificio['activo'] != true) {
          continue;
        }

        final idTipo = aInt(espacio['id_tipo_espacio']);

        final tipo = idTipo == null ? null : tiposPorId[idTipo];

        final nfc = nfcPorEspacio[idEspacio];

        final bool gpsConfigurado =
            espacio['radio_latitud'] != null &&
            espacio['radio_longitud'] != null;

        final bool nfcConfigurado =
            nfc != null && (nfc['uid_nfc'] ?? '').toString().trim().isNotEmpty;

        final bool configuracionCompleta = gpsConfigurado && nfcConfigurado;

        laboresTemporales.add({
          // -----------------------------------------------
          // ASIGNACIÓN
          // -----------------------------------------------

          'fechaAsignacion': asignacion['fecha_ini'],

          'comentarioAsignacion': asignacion['comentario'],

          // -----------------------------------------------
          // ESPACIO
          // -----------------------------------------------
          'idEspacio': idEspacio,

          'codigoEspacio': (espacio['codigo'] ?? '').toString(),

          'nombreEspacio': (espacio['nombre'] ?? 'Espacio').toString(),

          'tipoEspacio': (tipo?['nombre'] ?? 'Sin tipo').toString(),

          // -----------------------------------------------
          // PISO
          // -----------------------------------------------
          'idPiso': idPiso,

          'numeroPiso': piso['numero_nivel'],

          // -----------------------------------------------
          // EDIFICIO
          // -----------------------------------------------
          'idEdificio': idEdificio,

          'codigoEdificio': (edificio['codigo'] ?? '').toString(),

          'nombreEdificio': (edificio['nombre'] ?? 'Edificio').toString(),

          // -----------------------------------------------
          // GPS
          // -----------------------------------------------
          'radioLatitud': espacio['radio_latitud'],

          'radioLongitud': espacio['radio_longitud'],

          'radioMetros': espacio['radio_metros'] ?? 30,

          'gpsConfigurado': gpsConfigurado,

          // -----------------------------------------------
          // NFC
          // -----------------------------------------------
          'idNfc': nfc?['id_nfc'],

          'nfcUid': nfc?['uid_nfc']?.toString(),

          'nfcConfigurado': nfcConfigurado,

          // -----------------------------------------------
          // ESTADO GENERAL
          // -----------------------------------------------
          'configuracionCompleta': configuracionCompleta,
        });
      }

      // ---------------------------------------------------------
      // ORDENAR:
      // EDIFICIO → PISO → CÓDIGO
      // ---------------------------------------------------------

      laboresTemporales.sort((a, b) {
        final edificioA = a['codigoEdificio'].toString();

        final edificioB = b['codigoEdificio'].toString();

        final comparacionEdificio = edificioA.compareTo(edificioB);

        if (comparacionEdificio != 0) {
          return comparacionEdificio;
        }

        final pisoA = aInt(a['numeroPiso']) ?? 0;

        final pisoB = aInt(b['numeroPiso']) ?? 0;

        final comparacionPiso = pisoA.compareTo(pisoB);

        if (comparacionPiso != 0) {
          return comparacionPiso;
        }

        return a['codigoEspacio'].toString().compareTo(
          b['codigoEspacio'].toString(),
        );
      });

      if (!mounted) {
        return;
      }

      setState(() {
        labores = laboresTemporales;

        cargando = false;
      });
    } catch (error) {
      debugPrint(
        'ERROR CARGANDO LABORES: '
        '$error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;

        mensajeError = mensajeErrorLegible(error);
      });
    }
  }

  // =============================================================
  // ERROR LEGIBLE
  // =============================================================

  String mensajeErrorLegible(Object error) {
    final mensaje = error.toString();

    if (mensaje.startsWith('Exception: ')) {
      return mensaje.substring('Exception: '.length);
    }

    return 'No fue posible cargar tus labores disponibles.\n\n$mensaje';
  }

  // =============================================================
  // SELECCIONAR LABOR
  // =============================================================

  void seleccionarLabor(Map<String, dynamic> labor) {
    final bool configurada = labor['configuracionCompleta'] == true;

    if (!configurada) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            IniciarLaborPage(labor: Map<String, dynamic>.from(labor)),
      ),
    );
  }

  void abrirLaborNoAsignada() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const IniciarLaborPage(
          labor: <String, dynamic>{'esCobertura': true},
        ),
      ),
    );
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final total = labores.length;

    final listas = labores
        .where((labor) => labor['configuracionCompleta'] == true)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,

        surfaceTintColor: Colors.white,

        elevation: 0,

        title: const Text(
          'Labores disponibles',

          style: TextStyle(
            fontWeight: FontWeight.bold,

            color: Color(0xFF1F2937),
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Actualizar',

            onPressed: cargando ? null : cargarLabores,

            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 700),

            child: cargando
                ? const Center(child: CircularProgressIndicator())
                : mensajeError != null
                ? _ErrorLabores(
                    mensaje: mensajeError!,

                    onReintentar: cargarLabores,
                  )
                : Column(
                    children: [
                      // =================================
                      // CABECERA
                      // =================================

                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              'Hola, ${SesionData.primerNombreActual}',

                              style: const TextStyle(
                                fontSize: 25,

                                fontWeight: FontWeight.bold,

                                color: Color(0xFF1F2937),
                              ),
                            ),

                            const SizedBox(height: 6),

                            const Text(
                              'Selecciona el espacio donde realizarás la labor. '
                              'Luego RegiServ validará físicamente el NFC y tu ubicación.',

                              style: TextStyle(
                                fontSize: 14,

                                height: 1.45,

                                color: Color(0xFF6B7280),
                              ),
                            ),

                            const SizedBox(height: 18),

                            // =============================
                            // RESUMEN
                            // =============================
                            Container(
                              width: double.infinity,

                              padding: const EdgeInsets.all(16),

                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),

                                borderRadius: BorderRadius.circular(14),
                              ),

                              child: Wrap(
                                spacing: 24,

                                runSpacing: 10,

                                children: [
                                  _DatoResumen(
                                    icono: Icons.assignment_outlined,

                                    texto:
                                        '$total ${total == 1 ? 'labor asignada' : 'labores asignadas'}',
                                  ),

                                  _DatoResumen(
                                    icono: Icons.check_circle_outline,

                                    texto:
                                        '$listas ${listas == 1 ? 'lista para iniciar' : 'listas para iniciar'}',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // =================================
                      // COBERTURA EXCEPCIONAL
                      // =================================
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: abrirLaborNoAsignada,
                            icon: const Icon(Icons.nfc),
                            label: const Text('Realizar labor no asignada'),
                          ),
                        ),
                      ),

                      // =================================
                      // LISTADO
                      // =================================
                      Expanded(
                        child: labores.isEmpty
                            ? RefreshIndicator(
                                onRefresh: cargarLabores,

                                child: ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),

                                  children: const [
                                    SizedBox(height: 380, child: _SinLabores()),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: cargarLabores,

                                child: ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),

                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    4,
                                    20,
                                    30,
                                  ),

                                  itemCount: labores.length,

                                  itemBuilder: (context, index) {
                                    final labor = labores[index];

                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 14,
                                      ),

                                      child: _TarjetaLabor(
                                        labor: labor,

                                        onSeleccionar: () {
                                          seleccionarLabor(labor);
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
// TARJETA DE LABOR
// =================================================================

class _TarjetaLabor extends StatelessWidget {
  final Map<String, dynamic> labor;

  final VoidCallback onSeleccionar;

  const _TarjetaLabor({required this.labor, required this.onSeleccionar});

  @override
  Widget build(BuildContext context) {
    final gpsConfigurado = labor['gpsConfigurado'] == true;

    final nfcConfigurado = labor['nfcConfigurado'] == true;

    final configuracionCompleta = labor['configuracionCompleta'] == true;

    final codigo = labor['codigoEspacio'].toString();

    final nombre = labor['nombreEspacio'].toString();

    final tipo = labor['tipoEspacio'].toString();

    final edificio = labor['nombreEdificio'].toString();

    final piso = labor['numeroPiso'].toString();

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(
          color: configuracionCompleta
              ? const Color(0xFFBFDBFE)
              : const Color(0xFFE5E7EB),
        ),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // -------------------------------------------------------
          // CABECERA
          // -------------------------------------------------------

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Container(
                width: 50,

                height: 50,

                decoration: BoxDecoration(
                  color: configuracionCompleta
                      ? const Color(0xFFEFF6FF)
                      : const Color(0xFFF3F4F6),

                  borderRadius: BorderRadius.circular(13),
                ),

                child: Icon(
                  Icons.cleaning_services_outlined,

                  color: configuracionCompleta
                      ? const Color(0xFF1565C0)
                      : const Color(0xFF9CA3AF),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      nombre,

                      style: const TextStyle(
                        fontSize: 18,

                        fontWeight: FontWeight.bold,

                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      '$tipo · $codigo',

                      style: const TextStyle(
                        fontSize: 13,

                        color: Color(0xFF6B7280),
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      '$edificio · Piso $piso',

                      style: const TextStyle(
                        fontSize: 13,

                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,

                  vertical: 5,
                ),

                decoration: BoxDecoration(
                  color: configuracionCompleta
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFFFF7ED),

                  borderRadius: BorderRadius.circular(20),
                ),

                child: Text(
                  configuracionCompleta ? 'Disponible' : 'Pendiente',

                  style: TextStyle(
                    fontSize: 11,

                    fontWeight: FontWeight.w600,

                    color: configuracionCompleta
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFEA580C),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          const Divider(height: 1),

          const SizedBox(height: 14),

          // -------------------------------------------------------
          // ESTADO GPS / NFC
          // -------------------------------------------------------
          Wrap(
            spacing: 10,

            runSpacing: 8,

            children: [
              _EstadoFisico(
                icono: Icons.location_on_outlined,

                texto: gpsConfigurado ? 'GPS configurado' : 'GPS pendiente',

                correcto: gpsConfigurado,
              ),

              _EstadoFisico(
                icono: Icons.nfc_outlined,

                texto: nfcConfigurado ? 'NFC configurado' : 'NFC pendiente',

                correcto: nfcConfigurado,
              ),
            ],
          ),

          if (!configuracionCompleta) ...[
            const SizedBox(height: 12),

            const Text(
              'Esta labor todavía no puede iniciarse porque el espacio requiere completar su configuración física.',

              style: TextStyle(
                fontSize: 12,

                height: 1.4,

                color: Color(0xFF9A3412),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // -------------------------------------------------------
          // BOTÓN
          // -------------------------------------------------------
          SizedBox(
            width: double.infinity,

            child: ElevatedButton.icon(
              onPressed: configuracionCompleta ? onSeleccionar : null,

              icon: const Icon(Icons.arrow_forward),

              label: const Text('Seleccionar labor'),

              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),

                foregroundColor: Colors.white,

                padding: const EdgeInsets.symmetric(vertical: 14),

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// ESTADO FÍSICO
// =================================================================

class _EstadoFisico extends StatelessWidget {
  final IconData icono;
  final String texto;
  final bool correcto;

  const _EstadoFisico({
    required this.icono,
    required this.texto,
    required this.correcto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),

      decoration: BoxDecoration(
        color: correcto ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7ED),

        borderRadius: BorderRadius.circular(20),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(
            icono,

            size: 16,

            color: correcto ? const Color(0xFF16A34A) : const Color(0xFFEA580C),
          ),

          const SizedBox(width: 6),

          Text(
            texto,

            style: TextStyle(
              fontSize: 12,

              fontWeight: FontWeight.w500,

              color: correcto
                  ? const Color(0xFF166534)
                  : const Color(0xFF9A3412),
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// RESUMEN
// =================================================================

class _DatoResumen extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _DatoResumen({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,

      children: [
        Icon(icono, size: 20, color: const Color(0xFF1565C0)),

        const SizedBox(width: 7),

        Text(
          texto,

          style: const TextStyle(
            fontWeight: FontWeight.w600,

            color: Color(0xFF1E3A8A),
          ),
        ),
      ],
    );
  }
}

// =================================================================
// SIN LABORES
// =================================================================

class _SinLabores extends StatelessWidget {
  const _SinLabores();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            const Icon(
              Icons.assignment_outlined,

              size: 62,

              color: Color(0xFF9CA3AF),
            ),

            const SizedBox(height: 16),

            const Text(
              'No tienes labores disponibles',

              style: TextStyle(
                fontSize: 19,

                fontWeight: FontWeight.bold,

                color: Color(0xFF1F2937),
              ),
            ),

            const SizedBox(height: 7),

            const Text(
              'Cuando se te asignen espacios, aparecerán en esta pantalla.',

              textAlign: TextAlign.center,

              style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

// =================================================================
// ERROR
// =================================================================

class _ErrorLabores extends StatelessWidget {
  final String mensaje;

  final Future<void> Function() onReintentar;

  const _ErrorLabores({required this.mensaje, required this.onReintentar});

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
