import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/sesion_data.dart';

class MisSectoresAuxiliarPage extends StatefulWidget {
  const MisSectoresAuxiliarPage({super.key});

  @override
  State<MisSectoresAuxiliarPage> createState() =>
      _MisSectoresAuxiliarPageState();
}

class _MisSectoresAuxiliarPageState extends State<MisSectoresAuxiliarPage> {
  SupabaseClient get supabase => Supabase.instance.client;

  List<Map<String, dynamic>> sectores = [];

  int espaciosAsignados = 0;

  bool cargando = true;

  String? mensajeError;

  @override
  void initState() {
    super.initState();

    cargarSectores();
  }

  // =============================================================
  // CARGAR SECTORES REALES DESDE SUPABASE
  // =============================================================

  Future<void> cargarSectores() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;
      });
    }

    try {
      final usuarioAuth = supabase.auth.currentUser;

      if (usuarioAuth == null) {
        throw Exception('No existe una sesión autenticada en Supabase.');
      }

      final idUsuario = usuarioAuth.id;

      // ---------------------------------------------------------
      // PISOS VIGENTES DEL AUXILIAR
      // ---------------------------------------------------------

      final pisosTrabajadorData = await supabase
          .from('piso_trabajador')
          .select(
            'id_piso, '
            'fecha_ini, '
            'comentario',
          )
          .eq('id_usuario', idUsuario)
          .isFilter('fecha_fin', null);

      final List<Map<String, dynamic>> pisosTrabajador = [];

      for (final fila in pisosTrabajadorData) {
        pisosTrabajador.add(Map<String, dynamic>.from(fila));
      }

      // ---------------------------------------------------------
      // ESPACIOS VIGENTES DEL AUXILIAR
      // ---------------------------------------------------------

      final espaciosTrabajadorData = await supabase
          .from('espacio_trabajador')
          .select(
            'id_espacio, '
            'fecha_ini, '
            'comentario',
          )
          .eq('id_usuario', idUsuario)
          .isFilter('fecha_ter', null);

      final List<Map<String, dynamic>> espaciosTrabajador = [];

      for (final fila in espaciosTrabajadorData) {
        espaciosTrabajador.add(Map<String, dynamic>.from(fila));
      }

      final Set<String> idsEspaciosAsignados = espaciosTrabajador
          .map((fila) => fila['id_espacio'].toString())
          .toSet();

      // ---------------------------------------------------------
      // DATOS DE LOS ESPACIOS
      // ---------------------------------------------------------

      final Map<String, Map<String, dynamic>> espaciosPorId = {};

      if (idsEspaciosAsignados.isNotEmpty) {
        final espaciosData = await supabase
            .from('espacio')
            .select(
              'id_espacio, '
              'id_piso, '
              'id_tipo_espacio, '
              'codigo, '
              'nombre, '
              'activo',
            )
            .inFilter('id_espacio', idsEspaciosAsignados.toList());

        for (final fila in espaciosData) {
          final espacio = Map<String, dynamic>.from(fila);

          espaciosPorId[espacio['id_espacio'].toString()] = espacio;
        }
      }

      // ---------------------------------------------------------
      // PISOS NECESARIOS
      // ---------------------------------------------------------

      final Set<String> idsPisos = pisosTrabajador
          .map((fila) => fila['id_piso'].toString())
          .toSet();

      for (final espacio in espaciosPorId.values) {
        idsPisos.add(espacio['id_piso'].toString());
      }

      final Map<String, Map<String, dynamic>> pisosPorId = {};

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

          pisosPorId[piso['id_piso'].toString()] = piso;
        }
      }

      // ---------------------------------------------------------
      // EDIFICIOS NECESARIOS
      // ---------------------------------------------------------

      final Set<String> idsEdificios = pisosPorId.values
          .map((piso) => piso['id_edificio'].toString())
          .toSet();

      final Map<String, Map<String, dynamic>> edificiosPorId = {};

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

          edificiosPorId[edificio['id_edificio'].toString()] = edificio;
        }
      }

      // ---------------------------------------------------------
      // TIPOS DE ESPACIO NECESARIOS
      // ---------------------------------------------------------

      final Set<String> idsTipos = espaciosPorId.values
          .map((espacio) => espacio['id_tipo_espacio'].toString())
          .toSet();

      final Map<String, Map<String, dynamic>> tiposPorId = {};

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

          tiposPorId[tipo['id_tipo_espacio'].toString()] = tipo;
        }
      }

      // ---------------------------------------------------------
      // ASIGNACIONES DE ESPACIOS POR PISO
      // ---------------------------------------------------------

      final Map<String, List<Map<String, dynamic>>> espaciosPorPiso = {};

      for (final asignacionEspacio in espaciosTrabajador) {
        final idEspacio = asignacionEspacio['id_espacio'].toString();

        final espacio = espaciosPorId[idEspacio];

        if (espacio == null) {
          continue;
        }

        final idPiso = espacio['id_piso'].toString();

        final tipo = tiposPorId[espacio['id_tipo_espacio'].toString()];

        espaciosPorPiso.putIfAbsent(idPiso, () => []);

        espaciosPorPiso[idPiso]!.add({
          'idEspacio': espacio['id_espacio'],
          'nombreEspacio': espacio['nombre'] ?? 'Espacio',
          'codigoEspacio': espacio['codigo'] ?? '',
          'tipoEspacio': tipo?['nombre'] ?? 'Sin tipo',
          'fechaInicio': asignacionEspacio['fecha_ini'],
          'comentario': asignacionEspacio['comentario'],
        });
      }

      for (final lista in espaciosPorPiso.values) {
        lista.sort(
          (a, b) => a['codigoEspacio'].toString().compareTo(
            b['codigoEspacio'].toString(),
          ),
        );
      }

      // ---------------------------------------------------------
      // METADATOS DE PISO_TRABAJADOR
      // ---------------------------------------------------------

      final Map<String, Map<String, dynamic>> asignacionPisoPorId = {};

      for (final asignacionPiso in pisosTrabajador) {
        asignacionPisoPorId[asignacionPiso['id_piso'].toString()] =
            asignacionPiso;
      }

      // ---------------------------------------------------------
      // ARMAR SECTORES
      // ---------------------------------------------------------

      // Se usa la unión para que nunca quede oculto un espacio
      // vigente si existiera alguna inconsistencia histórica.
      final Set<String> idsPisosSector = {
        ...asignacionPisoPorId.keys,
        ...espaciosPorPiso.keys,
      };

      final List<Map<String, dynamic>> sectoresTemporales = [];

      for (final idPiso in idsPisosSector) {
        final piso = pisosPorId[idPiso];

        if (piso == null) {
          continue;
        }

        final edificio = edificiosPorId[piso['id_edificio'].toString()];

        if (edificio == null) {
          continue;
        }

        final asignacionPiso = asignacionPisoPorId[idPiso];

        sectoresTemporales.add({
          'idPiso': piso['id_piso'],
          'edificioCodigo': edificio['codigo'] ?? '',
          'edificioNombre': edificio['nombre'] ?? 'Edificio',
          'pisoNumero': piso['numero_nivel'] ?? '',
          'fechaInicio': asignacionPiso?['fecha_ini'],
          'comentario': asignacionPiso?['comentario'],
          'espacios': espaciosPorPiso[idPiso] ?? <Map<String, dynamic>>[],
        });
      }

      sectoresTemporales.sort((a, b) {
        final edificioA = a['edificioCodigo'].toString();

        final edificioB = b['edificioCodigo'].toString();

        final compararEdificio = edificioA.compareTo(edificioB);

        if (compararEdificio != 0) {
          return compararEdificio;
        }

        final pisoA = int.tryParse(a['pisoNumero'].toString()) ?? 0;

        final pisoB = int.tryParse(b['pisoNumero'].toString()) ?? 0;

        return pisoA.compareTo(pisoB);
      });

      if (!mounted) {
        return;
      }

      setState(() {
        sectores = sectoresTemporales;

        espaciosAsignados = espaciosTrabajador.length;

        cargando = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;
        mensajeError = _mensajeErrorLegible(error);
      });
    }
  }

  String _mensajeErrorLegible(Object error) {
    final texto = error.toString();

    if (texto.startsWith('Exception: ')) {
      return texto.substring('Exception: '.length);
    }

    return 'No fue posible cargar tus sectores.\n\n$texto';
  }

  @override
  Widget build(BuildContext context) {
    final usuario = SesionData.usuarioActual;

    if (usuario == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mis sectores')),
        body: const Center(
          child: Text('No existe una sesión de usuario activa.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,

        surfaceTintColor: Colors.white,

        title: const Text(
          'Mis sectores',

          style: TextStyle(
            fontWeight: FontWeight.bold,

            color: Color(0xFF1F2937),
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: cargando ? null : cargarSectores,
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
                ? _ErrorSectores(
                    mensaje: mensajeError!,
                    onReintentar: cargarSectores,
                  )
                : Column(
                    children: [
                      // =====================================
                      // CABECERA
                      // =====================================

                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              'Sectores de ${SesionData.primerNombreActual}',

                              style: const TextStyle(
                                fontSize: 24,

                                fontWeight: FontWeight.bold,

                                color: Color(0xFF1F2937),
                              ),
                            ),

                            const SizedBox(height: 6),

                            const Text(
                              'Estos son los pisos y espacios que actualmente están bajo tu responsabilidad.',

                              style: TextStyle(
                                color: Color(0xFF6B7280),

                                height: 1.4,
                              ),
                            ),

                            const SizedBox(height: 18),

                            // =================================
                            // RESUMEN
                            // =================================
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
                                  _DatoResumenSector(
                                    icono: Icons.layers_outlined,

                                    texto:
                                        '${sectores.length} ${sectores.length == 1 ? 'piso asignado' : 'pisos asignados'}',
                                  ),

                                  _DatoResumenSector(
                                    icono: Icons.meeting_room_outlined,

                                    texto:
                                        '$espaciosAsignados ${espaciosAsignados == 1 ? 'espacio asignado' : 'espacios asignados'}',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // =====================================
                      // LISTA
                      // =====================================
                      Expanded(
                        child: sectores.isEmpty
                            ? RefreshIndicator(
                                onRefresh: cargarSectores,
                                child: ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  children: const [
                                    SizedBox(
                                      height: 360,
                                      child: _SinSectores(),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: cargarSectores,
                                child: ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    4,
                                    20,
                                    30,
                                  ),
                                  itemCount: sectores.length,
                                  itemBuilder: (context, index) {
                                    final asignacion = sectores[index];

                                    final espacios =
                                        List<Map<String, dynamic>>.from(
                                          asignacion['espacios'] ??
                                              const <Map<String, dynamic>>[],
                                        );

                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 14,
                                      ),

                                      child: _TarjetaSectorAuxiliar(
                                        asignacion: asignacion,
                                        espacios: espacios,
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
// TARJETA DE SECTOR
// =================================================================

class _TarjetaSectorAuxiliar extends StatelessWidget {
  final Map<String, dynamic> asignacion;

  final List<Map<String, dynamic>> espacios;

  const _TarjetaSectorAuxiliar({
    required this.asignacion,
    required this.espacios,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),

      child: ExpansionTile(
        leading: Container(
          width: 46,
          height: 46,

          decoration: BoxDecoration(
            color: const Color(0xFFF0FDFA),

            borderRadius: BorderRadius.circular(12),
          ),

          child: const Icon(
            Icons.location_city_outlined,

            color: Color(0xFF0F766E),
          ),
        ),

        title: Text(
          '${asignacion['edificioNombre']} · Piso ${asignacion['pisoNumero']}',

          style: const TextStyle(
            fontWeight: FontWeight.bold,

            color: Color(0xFF1F2937),
          ),
        ),

        subtitle: Text(
          '${espacios.length} ${espacios.length == 1 ? 'espacio asignado' : 'espacios asignados'}',
        ),

        children: [
          const Divider(height: 1),

          if (espacios.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),

              child: Align(
                alignment: Alignment.centerLeft,

                child: Text('Este piso no tiene espacios vigentes asignados.'),
              ),
            )
          else
            for (final espacio in espacios)
              ListTile(
                leading: const Icon(
                  Icons.meeting_room_outlined,

                  color: Color(0xFF7C3AED),
                ),

                title: Text(espacio['nombreEspacio'].toString()),

                subtitle: Text(
                  '${espacio['tipoEspacio']} · ${espacio['codigoEspacio']}',
                ),

                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),

                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),

                    borderRadius: BorderRadius.circular(20),
                  ),

                  child: const Text(
                    'Asignado',

                    style: TextStyle(
                      fontSize: 11,

                      fontWeight: FontWeight.w600,

                      color: Color(0xFF16A34A),
                    ),
                  ),
                ),
              ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// =================================================================
// RESUMEN
// =================================================================

class _DatoResumenSector extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _DatoResumenSector({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,

      children: [
        Icon(icono, size: 19, color: const Color(0xFF1565C0)),

        const SizedBox(width: 7),

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
// ERROR
// =================================================================

class _ErrorSectores extends StatelessWidget {
  final String mensaje;
  final Future<void> Function() onReintentar;

  const _ErrorSectores({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 58, color: Color(0xFFDC2626)),
            const SizedBox(height: 14),
            const Text(
              'No fue posible cargar tus sectores',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
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
// SIN SECTORES
// =================================================================

class _SinSectores extends StatelessWidget {
  const _SinSectores();

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
              'No tienes sectores asignados',

              style: TextStyle(
                fontSize: 18,

                fontWeight: FontWeight.bold,

                color: Color(0xFF1F2937),
              ),
            ),

            SizedBox(height: 7),

            Text(
              'Consulta con el Supervisor Jefe para revisar tu asignación de trabajo.',

              textAlign: TextAlign.center,

              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
