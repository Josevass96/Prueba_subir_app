import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'detalle_registro_page.dart';

class HistorialAuxiliarPage extends StatefulWidget {
  const HistorialAuxiliarPage({super.key});

  @override
  State<HistorialAuxiliarPage> createState() => _HistorialAuxiliarPageState();
}

class _HistorialAuxiliarPageState extends State<HistorialAuxiliarPage> {
  SupabaseClient get supabase => Supabase.instance.client;

  final TextEditingController buscarController = TextEditingController();

  final List<Map<String, dynamic>> registros = <Map<String, dynamic>>[];

  bool cargando = true;
  String? mensajeError;

  String textoBusqueda = '';
  String filtroEstado = 'Todos';

  @override
  void initState() {
    super.initState();
    cargarHistorial();
  }

  @override
  void dispose() {
    buscarController.dispose();
    super.dispose();
  }

  // =============================================================
  // CARGAR HISTORIAL REAL
  // =============================================================

  Future<void> cargarHistorial() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;
      });
    }

    try {
      final dynamic respuesta = await supabase.rpc('listar_historial_auxiliar');

      final List<dynamic> filas = respuesta is List ? respuesta : <dynamic>[];

      final List<Map<String, dynamic>> temporales = <Map<String, dynamic>>[];

      for (final dynamic fila in filas) {
        if (fila is! Map) {
          continue;
        }

        final Map<String, dynamic> datos = Map<String, dynamic>.from(fila);

        final DateTime? inicio = _convertirFecha(datos['fecha_hora_inicio']);

        final DateTime? termino = _convertirFecha(datos['fecha_hora_fin']);

        final String codigo = _texto(
          datos['espacio_codigo'],
          defecto: 'Sin código',
        );

        final String nombre = _texto(datos['espacio_nombre'], defecto: codigo);

        final String estado = _texto(
          datos['estado_aseo'],
          defecto: 'Sin estado',
        );

        temporales.add(<String, dynamic>{
          'idRegistroAseo': datos['id_registro_aseo'],
          'idEspacio': datos['id_espacio'],
          'fechaOrden': termino ?? inicio,
          'fecha': _formatearFecha(inicio),
          'lugar': nombre,
          'codigoEspacio': codigo,
          'tipoEspacio': _texto(datos['tipo_espacio'], defecto: 'Sin tipo'),
          'inicio': _formatearHora(inicio),
          'termino': _formatearHora(termino),
          'duracion': _formatearDuracion(inicio, termino),
          'estado': estado,
          'estadoSincronizacion': _texto(
            datos['estado_sincronizacion'],
            defecto: 'Sincronizado',
          ),
          'nombreAuxiliar': _texto(
            datos['auxiliar_nombre'],
            defecto: 'Auxiliar',
          ),
          'motivoParcial': datos['motivo_parcial']?.toString(),
          'idObservacion': datos['id_observacion'],
          'categoriaObservacion': datos['categoria_observacion']?.toString(),
          'detalleObservacion': datos['detalle_observacion']?.toString(),
          'observacionAtendida': datos['observacion_atendida'] == true,
          'estadoAlerta': datos['estado_alerta']?.toString(),
        });
      }

      if (!mounted) {
        return;
      }

      setState(() {
        registros
          ..clear()
          ..addAll(temporales);

        cargando = false;

        if (filtroEstado != 'Todos' &&
            !estadosDisponibles.contains(filtroEstado)) {
          filtroEstado = 'Todos';
        }
      });
    } catch (error, stackTrace) {
      debugPrint('ERROR CARGANDO HISTORIAL AUXILIAR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;
        mensajeError = 'No fue posible cargar tu historial desde Supabase.';
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
      return '$horas h';
    }

    return '$horas h $minutos min';
  }

  // =============================================================
  // FILTROS
  // =============================================================

  List<String> get estadosDisponibles {
    final Set<String> estados = registros
        .map((registro) => registro['estado'].toString())
        .where((estado) => estado.trim().isNotEmpty)
        .toSet();

    final List<String> resultado = estados.toList()..sort();

    return <String>['Todos', ...resultado];
  }

  List<Map<String, dynamic>> get registrosFiltrados {
    final String busqueda = textoBusqueda.trim().toLowerCase();

    return registros.where((registro) {
      final String estado = registro['estado'].toString();

      final bool cumpleEstado =
          filtroEstado == 'Todos' || estado == filtroEstado;

      final String lugar = registro['lugar'].toString().toLowerCase();

      final String codigo = registro['codigoEspacio'].toString().toLowerCase();

      final String tipo = registro['tipoEspacio'].toString().toLowerCase();

      final String fecha = registro['fecha'].toString().toLowerCase();

      final bool cumpleBusqueda =
          busqueda.isEmpty ||
          lugar.contains(busqueda) ||
          codigo.contains(busqueda) ||
          tipo.contains(busqueda) ||
          fecha.contains(busqueda);

      return cumpleEstado && cumpleBusqueda;
    }).toList();
  }

  // =============================================================
  // ABRIR DETALLE
  // =============================================================

  void abrirRegistro(Map<String, dynamic> registro) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetalleRegistroPage(
          fecha: registro['fecha'].toString(),
          nombreAuxiliar: registro['nombreAuxiliar'].toString(),
          lugar: registro['lugar'].toString(),
          inicio: registro['inicio'].toString(),
          termino: registro['termino'].toString(),
          duracion: registro['duracion'].toString(),
          estado: registro['estado'].toString(),
          motivoParcial: registro['motivoParcial']?.toString(),
          categoriaObservacion: registro['categoriaObservacion']?.toString(),
          detalleObservacion: registro['detalleObservacion']?.toString(),
        ),
      ),
    );
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> lista = registrosFiltrados;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,

        title: const Text(
          'Mi historial',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: cargando ? null : cargarHistorial,
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
                // ===============================================
                // CABECERA + FILTROS
                // ===============================================

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      const Text(
                        'Mis registros',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        'Consulta las labores de aseo que has realizado.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                        ),
                      ),

                      const SizedBox(height: 18),

                      TextField(
                        controller: buscarController,

                        onChanged: (valor) {
                          setState(() {
                            textoBusqueda = valor;
                          });
                        },

                        decoration: InputDecoration(
                          hintText:
                              'Buscar por espacio, código, tipo o fecha...',

                          prefixIcon: const Icon(Icons.search),

                          filled: true,
                          fillColor: Colors.white,

                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        value: filtroEstado,
                        isExpanded: true,

                        decoration: InputDecoration(
                          labelText: 'Estado',

                          prefixIcon: const Icon(Icons.filter_alt_outlined),

                          filled: true,
                          fillColor: Colors.white,

                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),

                        items: estadosDisponibles
                            .map(
                              (estado) => DropdownMenuItem<String>(
                                value: estado,
                                child: Text(estado),
                              ),
                            )
                            .toList(),

                        onChanged: (valor) {
                          if (valor == null) {
                            return;
                          }

                          setState(() {
                            filtroEstado = valor;
                          });
                        },
                      ),

                      if (!cargando && mensajeError == null) ...[
                        const SizedBox(height: 12),

                        Text(
                          '${lista.length} '
                          '${lista.length == 1 ? 'registro encontrado' : 'registros encontrados'}',
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
                      ? _ErrorHistorial(
                          mensaje: mensajeError!,
                          onReintentar: cargarHistorial,
                        )
                      : lista.isEmpty
                      ? _SinRegistros(tieneRegistros: registros.isNotEmpty)
                      : RefreshIndicator(
                          onRefresh: cargarHistorial,

                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),

                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),

                            itemCount: lista.length,

                            itemBuilder: (context, index) {
                              final registro = lista[index];

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),

                                child: _TarjetaRegistro(
                                  registro: registro,

                                  onTap: () {
                                    abrirRegistro(registro);
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
// TARJETA
// =================================================================

class _TarjetaRegistro extends StatelessWidget {
  final Map<String, dynamic> registro;
  final VoidCallback onTap;

  const _TarjetaRegistro({required this.registro, required this.onTap});

  Color obtenerColorEstado() {
    switch (registro['estado']) {
      case 'Completo':
        return const Color(0xFF16A34A);

      case 'Parcial':
        return const Color(0xFFD97706);

      case 'Con Observaciones':
        return const Color(0xFFDC2626);

      case 'Incompleta - Cerrada por Supervisor':
        return const Color(0xFF7C3AED);

      default:
        return const Color(0xFF6B7280);
    }
  }

  Color obtenerFondoEstado() {
    switch (registro['estado']) {
      case 'Completo':
        return const Color(0xFFF0FDF4);

      case 'Parcial':
        return const Color(0xFFFFFBEB);

      case 'Con Observaciones':
        return const Color(0xFFFEF2F2);

      case 'Incompleta - Cerrada por Supervisor':
        return const Color(0xFFF5F3FF);

      default:
        return const Color(0xFFF3F4F6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color colorEstado = obtenerColorEstado();

    final Color fondoEstado = obtenerFondoEstado();

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
              // FECHA + ESTADO
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Expanded(
                    child: Text(
                      registro['fecha'].toString(),

                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),

                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),

                      decoration: BoxDecoration(
                        color: fondoEstado,

                        borderRadius: BorderRadius.circular(20),
                      ),

                      child: Text(
                        registro['estado'].toString(),

                        textAlign: TextAlign.center,

                        style: TextStyle(
                          color: colorEstado,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // LUGAR
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: Color(0xFF1565C0),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        Text(
                          registro['lugar'].toString(),

                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),

                        const SizedBox(height: 2),

                        Text(
                          '${registro['tipoEspacio']} · '
                          '${registro['codigoEspacio']}',

                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
                ],
              ),

              if (registro['estado'] == 'Con Observaciones' &&
                  registro['estadoAlerta'] != null) ...[
                const SizedBox(height: 12),

                _EstadoObservacion(estado: registro['estadoAlerta'].toString()),
              ],

              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 12),

              // HORARIOS
              Row(
                children: [
                  Expanded(
                    child: _DatoRegistro(
                      titulo: 'Inicio',
                      valor: registro['inicio'].toString(),
                    ),
                  ),

                  Expanded(
                    child: _DatoRegistro(
                      titulo: 'Término',
                      valor: registro['termino'].toString(),
                    ),
                  ),

                  Expanded(
                    child: _DatoRegistro(
                      titulo: 'Duración',
                      valor: registro['duracion'].toString(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =================================================================
// ESTADO DE OBSERVACIÓN
// =================================================================

class _EstadoObservacion extends StatelessWidget {
  final String estado;

  const _EstadoObservacion({required this.estado});

  @override
  Widget build(BuildContext context) {
    final bool atendida = estado == 'Atendida' || estado == 'Resuelta';

    final bool leida = estado == 'Leída' || estado == 'En atención';

    final Color color = atendida
        ? const Color(0xFF16A34A)
        : leida
        ? const Color(0xFFD97706)
        : const Color(0xFFDC2626);

    final Color fondo = atendida
        ? const Color(0xFFF0FDF4)
        : leida
        ? const Color(0xFFFFFBEB)
        : const Color(0xFFFEF2F2);

    final IconData icono = atendida
        ? Icons.check_circle_outline
        : leida
        ? Icons.mark_email_read_outlined
        : Icons.warning_amber_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),

      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(10),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(icono, size: 17, color: color),

          const SizedBox(width: 7),

          Flexible(
            child: Text(
              'Observación: $estado',

              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// DATO
// =================================================================

class _DatoRegistro extends StatelessWidget {
  final String titulo;
  final String valor;

  const _DatoRegistro({required this.titulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Text(
          titulo,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),

        const SizedBox(height: 4),

        Text(
          valor,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }
}

// =================================================================
// ERROR
// =================================================================

class _ErrorHistorial extends StatelessWidget {
  final String mensaje;
  final Future<void> Function() onReintentar;

  const _ErrorHistorial({required this.mensaje, required this.onReintentar});

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
// VACÍO
// =================================================================

class _SinRegistros extends StatelessWidget {
  final bool tieneRegistros;

  const _SinRegistros({required this.tieneRegistros});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            const Icon(Icons.history, size: 56, color: Color(0xFF9CA3AF)),

            const SizedBox(height: 14),

            Text(
              tieneRegistros
                  ? 'No hay coincidencias'
                  : 'Aún no tienes registros',

              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),

            const SizedBox(height: 6),

            Text(
              tieneRegistros
                  ? 'Prueba con otro término de búsqueda o estado.'
                  : 'Cuando finalices una labor aparecerá aquí.',

              textAlign: TextAlign.center,

              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
