import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'detalle_registro_supervisor_page.dart';

class AlertasSupervisorPage extends StatefulWidget {
  const AlertasSupervisorPage({super.key});

  @override
  State<AlertasSupervisorPage> createState() => _AlertasSupervisorPageState();
}

class _AlertasSupervisorPageState extends State<AlertasSupervisorPage> {
  SupabaseClient get supabase => Supabase.instance.client;

  final List<Map<String, dynamic>> alertas = <Map<String, dynamic>>[];

  bool cargando = true;
  String? mensajeError;

  String filtroSeleccionado = 'Todas';

  // =============================================================
  // INICIALIZACIÓN
  // =============================================================

  @override
  void initState() {
    super.initState();
    cargarAlertas();
  }

  // =============================================================
  // CARGAR ALERTAS REALES
  // =============================================================

  Future<void> cargarAlertas() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;
      });
    }

    try {
      final dynamic respuesta = await supabase.rpc(
        'listar_alertas_supervision',
      );

      final List<dynamic> filas = respuesta is List ? respuesta : <dynamic>[];

      final List<Map<String, dynamic>> alertasTemporales =
          <Map<String, dynamic>>[];

      for (final dynamic fila in filas) {
        if (fila is! Map) {
          continue;
        }

        final Map<String, dynamic> datos = Map<String, dynamic>.from(fila);

        final DateTime? fechaAlerta = _convertirFecha(datos['fecha_alerta']);

        final DateTime? inicio = _convertirFecha(datos['fecha_hora_inicio']);

        final DateTime? termino = _convertirFecha(datos['fecha_hora_fin']);

        final String codigo = _texto(
          datos['espacio_codigo'],
          defecto: 'Sin código',
        );

        final String nombre = _texto(datos['espacio_nombre'], defecto: codigo);

        final String lugar = nombre.trim().isEmpty ? codigo : nombre;

        final String estado = _texto(
          datos['estado_alerta'],
          defecto: 'Pendiente',
        );

        alertasTemporales.add(<String, dynamic>{
          'idAlerta': datos['id_alerta'],
          'idObservacion': datos['id_observacion'],
          'idRegistroAseo': datos['id_registro_aseo'],
          'fecha': _formatearFecha(fechaAlerta),
          'hora': _formatearHora(fechaAlerta),
          'fechaOrden': fechaAlerta,
          'lugar': lugar,
          'codigoEspacio': codigo,
          'tipo': _texto(datos['tipo_espacio'], defecto: 'Sin tipo'),
          'responsable': _texto(
            datos['responsable'],
            defecto: 'Sin responsable',
          ),
          'inicio': _formatearHora(inicio),
          'termino': _formatearHora(termino),
          'duracion': _formatearDuracion(inicio, termino),
          'categoria': _texto(
            datos['categoria_observacion'],
            defecto: 'Sin categoría',
          ),
          'detalle': _texto(
            datos['detalle_observacion'],
            defecto: 'Sin detalle',
          ),
          'estado': estado,
          'observacionAtendida': datos['observacion_atendida'] == true,
        });
      }

      if (!mounted) {
        return;
      }

      setState(() {
        alertas
          ..clear()
          ..addAll(alertasTemporales);

        cargando = false;
      });
    } catch (error, stackTrace) {
      debugPrint('ERROR CARGANDO ALERTAS SUPERVISOR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;
        mensajeError = 'No fue posible cargar las alertas desde Supabase.';
      });
    }
  }

  // =============================================================
  // UTILIDADES
  // =============================================================

  String _texto(dynamic valor, {required String defecto}) {
    if (valor == null) {
      return defecto;
    }

    final String texto = valor.toString().trim();

    return texto.isEmpty ? defecto : texto;
  }

  DateTime? _convertirFecha(dynamic valor) {
    if (valor == null) {
      return null;
    }

    try {
      return DateTime.parse(valor.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _formatearFecha(DateTime? fecha) {
    if (fecha == null) {
      return '-';
    }

    final String dia = fecha.day.toString().padLeft(2, '0');

    final String mes = fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  String _formatearHora(DateTime? fecha) {
    if (fecha == null) {
      return '-';
    }

    final String hora = fecha.hour.toString().padLeft(2, '0');

    final String minuto = fecha.minute.toString().padLeft(2, '0');

    return '$hora:$minuto';
  }

  String _formatearDuracion(DateTime? inicio, DateTime? termino) {
    if (inicio == null || termino == null) {
      return '-';
    }

    final Duration duracion = termino.difference(inicio);

    if (duracion.isNegative) {
      return '-';
    }

    if (duracion.inMinutes < 1) {
      return '< 1 min';
    }

    final int horas = duracion.inHours;
    final int minutos = duracion.inMinutes.remainder(60);

    if (horas == 0) {
      return '${duracion.inMinutes} min';
    }

    if (minutos == 0) {
      return '${horas} h';
    }

    return '${horas} h ${minutos} min';
  }

  // =============================================================
  // FILTRAR ALERTAS
  // =============================================================

  List<Map<String, dynamic>> get alertasFiltradas {
    if (filtroSeleccionado == 'Por atender') {
      return alertas.where((alerta) {
        final String estado = alerta['estado'].toString();

        return estado == 'Pendiente' ||
            estado == 'Leída' ||
            estado == 'En atención';
      }).toList();
    }

    if (filtroSeleccionado == 'En atención') {
      return alertas.where((alerta) {
        return alerta['estado'] == 'En atención';
      }).toList();
    }

    if (filtroSeleccionado == 'Atendidas') {
      return alertas.where((alerta) {
        final String estado = alerta['estado'].toString();

        return estado == 'Atendida' || estado == 'Resuelta';
      }).toList();
    }

    return alertas;
  }

  int get pendientes {
    return alertas.where((alerta) {
      final String estado = alerta['estado'].toString();

      return estado != 'Atendida' && estado != 'Resuelta';
    }).length;
  }

  // =============================================================
  // ABRIR ALERTA
  // =============================================================

  Future<void> abrirAlerta(Map<String, dynamic> alerta) async {
    final int? idRegistro = int.tryParse(alerta['idRegistroAseo'].toString());

    if (idRegistro == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible identificar el registro asociado.'),
        ),
      );

      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetalleRegistroSupervisorPage(
          idRegistroAseo: idRegistro,
          fecha: alerta['fecha'].toString(),
          responsable: alerta['responsable'].toString(),
          lugar: alerta['lugar'].toString(),
          inicio: alerta['inicio'].toString(),
          termino: alerta['termino'].toString(),
          duracion: alerta['duracion'].toString(),
          estado: 'Con Observaciones',
          categoriaObservacion: alerta['categoria'].toString(),
          detalleObservacion: alerta['detalle'].toString(),
          estadoAlerta: alerta['estado'].toString(),
          onEstadoObservacionChanged: (nuevoEstado) {
            if (!mounted) {
              return;
            }

            setState(() {
              alerta['estado'] = nuevoEstado;
            });
          },
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    // Recargamos desde Supabase para que el estado visible
    // siempre sea el persistido realmente.
    await cargarAlertas();
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> lista = alertasFiltradas;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,

        title: const Text(
          'Alertas',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: cargando ? null : cargarAlertas,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 700),

            child: Column(
              children: [
                // ===============================================
                // CABECERA
                // ===============================================

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      const Text(
                        'Observaciones reportadas',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        'Revisa las observaciones informadas por los Auxiliares al finalizar una labor.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: Color(0xFF6B7280),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // =========================================
                      // RESUMEN
                      // =========================================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),

                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(14),
                        ),

                        child: Row(
                          children: [
                            const Icon(
                              Icons.notifications_active_outlined,
                              color: Color(0xFFDC2626),
                              size: 30,
                            ),

                            const SizedBox(width: 14),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [
                                  Text(
                                    '$pendientes '
                                    '${pendientes == 1 ? 'alerta sin resolver' : 'alertas sin resolver'}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF991B1B),
                                    ),
                                  ),

                                  const SizedBox(height: 3),

                                  const Text(
                                    'Incluye alertas pendientes, leídas y en atención.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFB91C1C),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // =========================================
                      // FILTROS
                      // =========================================
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,

                        child: Row(
                          children: [
                            _FiltroAlerta(
                              texto: 'Todas',
                              seleccionado: filtroSeleccionado == 'Todas',
                              onTap: () {
                                setState(() {
                                  filtroSeleccionado = 'Todas';
                                });
                              },
                            ),

                            const SizedBox(width: 8),

                            _FiltroAlerta(
                              texto: 'Por atender',
                              seleccionado: filtroSeleccionado == 'Por atender',
                              onTap: () {
                                setState(() {
                                  filtroSeleccionado = 'Por atender';
                                });
                              },
                            ),

                            const SizedBox(width: 8),

                            _FiltroAlerta(
                              texto: 'En atención',
                              seleccionado: filtroSeleccionado == 'En atención',
                              onTap: () {
                                setState(() {
                                  filtroSeleccionado = 'En atención';
                                });
                              },
                            ),

                            const SizedBox(width: 8),

                            _FiltroAlerta(
                              texto: 'Atendidas',
                              seleccionado: filtroSeleccionado == 'Atendidas',
                              onTap: () {
                                setState(() {
                                  filtroSeleccionado = 'Atendidas';
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                      if (!cargando && mensajeError == null) ...[
                        const SizedBox(height: 12),

                        Text(
                          '${lista.length} ${lista.length == 1 ? 'alerta encontrada' : 'alertas encontradas'}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ===============================================
                // LISTADO
                // ===============================================
                Expanded(
                  child: cargando
                      ? const Center(child: CircularProgressIndicator())
                      : mensajeError != null
                      ? _ErrorAlertas(
                          mensaje: mensajeError!,
                          onReintentar: cargarAlertas,
                        )
                      : lista.isEmpty
                      ? _SinAlertas(filtro: filtroSeleccionado)
                      : RefreshIndicator(
                          onRefresh: cargarAlertas,

                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),

                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),

                            itemCount: lista.length,

                            itemBuilder: (context, index) {
                              final Map<String, dynamic> alerta = lista[index];

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),

                                child: _TarjetaAlerta(
                                  alerta: alerta,

                                  onTap: () {
                                    abrirAlerta(alerta);
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
// FILTRO
// =================================================================

class _FiltroAlerta extends StatelessWidget {
  final String texto;
  final bool seleccionado;
  final VoidCallback onTap;

  const _FiltroAlerta({
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
// TARJETA DE ALERTA
// =================================================================

class _TarjetaAlerta extends StatelessWidget {
  final Map<String, dynamic> alerta;
  final VoidCallback onTap;

  const _TarjetaAlerta({required this.alerta, required this.onTap});

  Color obtenerColor() {
    switch (alerta['estado']) {
      case 'Pendiente':
        return const Color(0xFFDC2626);

      case 'Leída':
        return const Color(0xFFD97706);

      case 'En atención':
        return const Color(0xFF2563EB);

      case 'Atendida':
      case 'Resuelta':
        return const Color(0xFF16A34A);

      default:
        return const Color(0xFF6B7280);
    }
  }

  Color obtenerFondo() {
    switch (alerta['estado']) {
      case 'Pendiente':
        return const Color(0xFFFEF2F2);

      case 'Leída':
        return const Color(0xFFFFFBEB);

      case 'En atención':
        return const Color(0xFFEFF6FF);

      case 'Atendida':
      case 'Resuelta':
        return const Color(0xFFF0FDF4);

      default:
        return const Color(0xFFF3F4F6);
    }
  }

  IconData obtenerIconoEstado() {
    switch (alerta['estado']) {
      case 'Atendida':
      case 'Resuelta':
        return Icons.check_circle_outline;

      case 'Leída':
        return Icons.mark_email_read_outlined;

      case 'En atención':
        return Icons.pending_actions_outlined;

      default:
        return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = obtenerColor();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),

      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),

        child: Container(
          padding: const EdgeInsets.all(18),

          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),

            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              // ===============================================
              // FECHA + ESTADO
              // ===============================================

              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${alerta['fecha']} · ${alerta['hora']}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),

                    decoration: BoxDecoration(
                      color: obtenerFondo(),
                      borderRadius: BorderRadius.circular(20),
                    ),

                    child: Row(
                      mainAxisSize: MainAxisSize.min,

                      children: [
                        Icon(obtenerIconoEstado(), size: 14, color: color),

                        const SizedBox(width: 5),

                        Text(
                          alerta['estado'].toString(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ===============================================
              // LUGAR
              // ===============================================
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: Color(0xFF1565C0),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      alerta['lugar'].toString(),

                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),

                  const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
                ],
              ),

              const SizedBox(height: 5),

              Padding(
                padding: const EdgeInsets.only(left: 32),

                child: Text(
                  alerta['tipo'].toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ===============================================
              // AUXILIAR
              // ===============================================
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 20,
                    color: Color(0xFF6B7280),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      alerta['responsable'].toString(),

                      style: const TextStyle(color: Color(0xFF4B5563)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // ===============================================
              // CATEGORÍA + DETALLE
              // ===============================================
              Text(
                alerta['categoria'].toString(),

                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),

              if (alerta['categoria'] == 'Daño a infraestructura') ...[
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(
                      Icons.engineering_outlined,
                      color: Color(0xFF2563EB),
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Seguimiento por Mantención',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 6),

              Text(
                alerta['detalle'].toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,

                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Color(0xFF4B5563),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =================================================================
// ERROR
// =================================================================

class _ErrorAlertas extends StatelessWidget {
  final String mensaje;
  final Future<void> Function() onReintentar;

  const _ErrorAlertas({required this.mensaje, required this.onReintentar});

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
              size: 54,
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
// SIN ALERTAS
// =================================================================

class _SinAlertas extends StatelessWidget {
  final String filtro;

  const _SinAlertas({required this.filtro});

  @override
  Widget build(BuildContext context) {
    String mensaje;

    switch (filtro) {
      case 'Por atender':
        mensaje = 'No hay observaciones pendientes de atención.';
        break;

      case 'Atendidas':
        mensaje = 'Aún no hay observaciones atendidas.';
        break;

      default:
        mensaje = 'Aún no existen observaciones registradas.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            const Icon(
              Icons.notifications_none_outlined,
              size: 56,
              color: Color(0xFF9CA3AF),
            ),

            const SizedBox(height: 14),

            const Text(
              'No hay alertas',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),

            const SizedBox(height: 6),

            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
