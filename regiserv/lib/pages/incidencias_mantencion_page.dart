import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'detalle_incidencia_mantencion_page.dart';

class IncidenciasMantencionPage extends StatefulWidget {
  const IncidenciasMantencionPage({super.key});

  @override
  State<IncidenciasMantencionPage> createState() =>
      _IncidenciasMantencionPageState();
}

class _IncidenciasMantencionPageState extends State<IncidenciasMantencionPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  final List<Map<String, dynamic>> incidencias = <Map<String, dynamic>>[];

  bool cargando = true;
  String? mensajeError;

  String filtro = 'Por atender';

  @override
  void initState() {
    super.initState();
    cargarIncidencias();
  }

  String _texto(dynamic valor, {String defecto = '—'}) {
    if (valor == null) {
      return defecto;
    }

    final String texto = valor.toString().trim();
    return texto.isEmpty ? defecto : texto;
  }

  DateTime? _fecha(dynamic valor) {
    if (valor == null) {
      return null;
    }

    try {
      return DateTime.parse(valor.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _fechaHora(dynamic valor) {
    final DateTime? fecha = _fecha(valor);

    if (fecha == null) {
      return 'Sin fecha';
    }

    final String dia = fecha.day.toString().padLeft(2, '0');
    final String mes = fecha.month.toString().padLeft(2, '0');
    final String hora = fecha.hour.toString().padLeft(2, '0');
    final String minuto = fecha.minute.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year} $hora:$minuto';
  }

  String _ubicacion(Map<String, dynamic> datos) {
    final String edificio = _texto(datos['edificio'], defecto: 'Sin edificio');

    final String piso = datos['numero_nivel'] == null
        ? 'Sin piso'
        : 'Piso ${datos['numero_nivel']}';

    final String espacio = _texto(
      datos['espacio_nombre'],
      defecto: _texto(datos['espacio_codigo'], defecto: 'Sin espacio'),
    );

    return '$edificio · $piso · $espacio';
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'En atención':
        return const Color(0xFF2563EB);
      case 'Resuelta':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFFD97706);
    }
  }

  Color _fondoEstado(String estado) {
    switch (estado) {
      case 'En atención':
        return const Color(0xFFEFF6FF);
      case 'Resuelta':
        return const Color(0xFFF0FDF4);
      default:
        return const Color(0xFFFFFBEB);
    }
  }

  List<Map<String, dynamic>> get incidenciasFiltradas {
    switch (filtro) {
      case 'En atención':
        return incidencias
            .where(
              (item) =>
                  _texto(item['estado_alerta'], defecto: 'Pendiente') ==
                  'En atención',
            )
            .toList();

      case 'Resueltas':
        return incidencias
            .where(
              (item) =>
                  _texto(item['estado_alerta'], defecto: 'Pendiente') ==
                  'Resuelta',
            )
            .toList();

      case 'Todas':
        return List<Map<String, dynamic>>.from(incidencias);

      default:
        return incidencias.where((item) {
          final String estado = _texto(
            item['estado_alerta'],
            defecto: 'Pendiente',
          );

          return estado != 'En atención' && estado != 'Resuelta';
        }).toList();
    }
  }

  Future<void> cargarIncidencias() async {
    if (!mounted) {
      return;
    }

    setState(() {
      cargando = true;
      mensajeError = null;
    });

    try {
      final dynamic respuesta = await supabase.rpc(
        'listar_incidencias_mantencion',
      );

      final List<dynamic> filas = respuesta is List ? respuesta : <dynamic>[];

      final List<Map<String, dynamic>> nuevas = <Map<String, dynamic>>[];

      for (final dynamic fila in filas) {
        if (fila is! Map) {
          continue;
        }

        nuevas.add(Map<String, dynamic>.from(fila));
      }

      if (!mounted) {
        return;
      }

      setState(() {
        incidencias
          ..clear()
          ..addAll(nuevas);

        cargando = false;
        mensajeError = null;
      });
    } catch (error, stackTrace) {
      debugPrint('ERROR cargarIncidenciasMantencion: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        incidencias.clear();
        cargando = false;
        mensajeError = 'No fue posible cargar las incidencias.';
      });
    }
  }

  Future<void> abrirDetalle(Map<String, dynamic> incidencia) async {
    final int? idAlerta = int.tryParse(
      incidencia['id_alerta']?.toString() ?? '',
    );

    if (idAlerta == null) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            DetalleIncidenciaMantencionPage(idAlerta: idAlerta),
      ),
    );

    if (!mounted) {
      return;
    }

    await cargarIncidencias();
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> visibles = incidenciasFiltradas;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Incidencias',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        actions: [
          IconButton(
            onPressed: cargando ? null : cargarIncidencias,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: cargarIncidencias,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gestión de incidencias',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Revisa todos los daños de infraestructura derivados a Mantención.',
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 20),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final String opcion in <String>[
                          'Por atender',
                          'En atención',
                          'Resueltas',
                          'Todas',
                        ])
                          ChoiceChip(
                            label: Text(opcion),
                            selected: filtro == opcion,
                            onSelected: (_) {
                              setState(() {
                                filtro = opcion;
                              });
                            },
                          ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    if (cargando)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 50),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (mensajeError != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 42,
                              color: Color(0xFFDC2626),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              mensajeError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF991B1B)),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: cargarIncidencias,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      )
                    else if (visibles.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: const Column(
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 44,
                              color: Color(0xFF9CA3AF),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'No hay incidencias en esta categoría.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Text(
                        '${visibles.length} ${visibles.length == 1 ? 'incidencia' : 'incidencias'}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...visibles.map((incidencia) {
                        final String estado = _texto(
                          incidencia['estado_alerta'],
                          defecto: 'Pendiente',
                        );

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                abrirDetalle(incidencia);
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFE5E7EB),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.construction_outlined,
                                          color: Color(0xFFD97706),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _texto(
                                              incidencia['categoria_observacion'],
                                              defecto: 'Daño a infraestructura',
                                            ),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1F2937),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _fondoEstado(estado),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Text(
                                            estado,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _colorEstado(estado),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _texto(
                                        incidencia['detalle_observacion'],
                                        defecto: 'Sin detalle',
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF374151),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _ubicacion(incidencia),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.schedule_outlined,
                                          size: 15,
                                          color: Color(0xFF9CA3AF),
                                        ),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(
                                            _fechaHora(
                                              incidencia['fecha_alerta'],
                                            ),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF6B7280),
                                            ),
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right,
                                          color: Color(0xFF9CA3AF),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
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
