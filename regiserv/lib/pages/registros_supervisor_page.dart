import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'detalle_registro_supervisor_page.dart';

class RegistrosSupervisorPage extends StatefulWidget {
  const RegistrosSupervisorPage({super.key});

  @override
  State<RegistrosSupervisorPage> createState() =>
      _RegistrosSupervisorPageState();
}

class _RegistrosSupervisorPageState extends State<RegistrosSupervisorPage> {
  SupabaseClient get supabase => Supabase.instance.client;

  final List<Map<String, dynamic>> registros = <Map<String, dynamic>>[];

  bool cargando = true;
  String? mensajeError;

  // =============================================================
  // FILTROS
  // =============================================================

  String filtroFecha = 'Todas';
  String filtroHorario = 'Todos';
  String filtroLugar = 'Todos';
  String filtroResponsable = 'Todos';
  String filtroEstado = 'Todos';
  String filtroTipo = 'Todos';

  // =============================================================
  // INICIALIZACIÓN
  // =============================================================

  @override
  void initState() {
    super.initState();
    cargarRegistros();
  }

  // =============================================================
  // CARGAR REGISTROS REALES
  // =============================================================

  Future<void> cargarRegistros() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;
      });
    }

    try {
      final dynamic respuesta = await supabase.rpc(
        'listar_registros_supervision',
      );

      final List<dynamic> filas = respuesta is List ? respuesta : <dynamic>[];

      final List<Map<String, dynamic>> registrosTemporales =
          <Map<String, dynamic>>[];

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

        final String lugar = nombre.trim().isEmpty ? codigo : nombre;

        final String estado = _texto(
          datos['estado_aseo'],
          defecto: 'Sin estado',
        );

        registrosTemporales.add(<String, dynamic>{
          'idRegistroAseo': datos['id_registro_aseo'],
          'idUsuario': datos['id_usuario']?.toString(),
          'idEspacio': datos['id_espacio'],
          'fecha': _formatearFecha(inicio),
          'fechaOrden': inicio,
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
          'estado': estado,
          'horario': _obtenerHorario(inicio),
          'estadoSincronizacion': _texto(
            datos['estado_sincronizacion'],
            defecto: 'Sincronizado',
          ),
          'motivoParcial': datos['motivo_parcial']?.toString(),
          'idObservacion': datos['id_observacion'],
          'categoriaObservacion': datos['categoria_observacion']?.toString(),
          'detalleObservacion': datos['detalle_observacion']?.toString(),
          'observacionAtendida': datos['observacion_atendida'] == true,
          'estadoAlerta': datos['estado_alerta']?.toString(),
        });
      }

      // Consultar solamente la marca de cobertura, sin cambiar
      // la RPC que hoy lista registros y observaciones.
      final List<int> ids = registrosTemporales
          .map((fila) => int.tryParse('${fila['idRegistroAseo']}'))
          .whereType<int>()
          .toList();
      final Set<int> idsCobertura = <int>{};
      if (ids.isNotEmpty) {
        final dynamic marcas = await supabase
            .from('registro_aseo')
            .select('id_registro_aseo, es_cobertura')
            .inFilter('id_registro_aseo', ids);
        if (marcas is List) {
          for (final dynamic marca in marcas) {
            if (marca is Map && marca['es_cobertura'] == true) {
              final int? id = int.tryParse('${marca['id_registro_aseo']}');
              if (id != null) idsCobertura.add(id);
            }
          }
        }
      }
      for (final registro in registrosTemporales) {
        final int? id = int.tryParse('${registro['idRegistroAseo']}');
        registro['esCobertura'] = id != null && idsCobertura.contains(id);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        registros
          ..clear()
          ..addAll(registrosTemporales);

        cargando = false;

        _corregirFiltrosSiYaNoExisten();
      });
    } catch (error, stackTrace) {
      debugPrint('ERROR CARGANDO REGISTROS SUPERVISOR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;
        mensajeError =
            'No fue posible cargar los registros de aseo desde Supabase.';
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

  String _obtenerHorario(DateTime? inicio) {
    if (inicio == null) {
      return 'Sin horario';
    }

    if (inicio.hour < 12) {
      return 'Mañana';
    }

    if (inicio.hour < 18) {
      return 'Tarde';
    }

    return 'Noche';
  }

  // =============================================================
  // OPCIONES DE FILTROS REALES
  // =============================================================

  List<String> get fechasDisponibles {
    final List<String> resultado = <String>[];

    for (final Map<String, dynamic> registro in registros) {
      final String fecha = registro['fecha'].toString();

      if (!resultado.contains(fecha)) {
        resultado.add(fecha);
      }
    }

    return <String>['Todas', ...resultado];
  }

  List<String> get horariosDisponibles {
    final List<String> resultado = registros
        .map((registro) => registro['horario'].toString())
        .where((valor) => valor != 'Sin horario')
        .toSet()
        .toList();

    const List<String> orden = <String>['Mañana', 'Tarde', 'Noche'];

    resultado.sort((a, b) => orden.indexOf(a).compareTo(orden.indexOf(b)));

    return <String>['Todos', ...resultado];
  }

  List<String> get lugaresDisponibles {
    final List<String> resultado =
        registros
            .map((registro) => registro['lugar'].toString())
            .toSet()
            .toList()
          ..sort();

    return <String>['Todos', ...resultado];
  }

  List<String> get responsablesDisponibles {
    final List<String> resultado =
        registros
            .map((registro) => registro['responsable'].toString())
            .toSet()
            .toList()
          ..sort();

    return <String>['Todos', ...resultado];
  }

  List<String> get estadosDisponibles {
    final List<String> resultado = registros
        .map((registro) => registro['estado'].toString())
        .toSet()
        .toList();

    const List<String> orden = <String>[
      'Completo',
      'Parcial',
      'Con Observaciones',
    ];

    resultado.sort((a, b) {
      final int indiceA = orden.indexOf(a);
      final int indiceB = orden.indexOf(b);

      if (indiceA == -1 && indiceB == -1) {
        return a.compareTo(b);
      }

      if (indiceA == -1) {
        return 1;
      }

      if (indiceB == -1) {
        return -1;
      }

      return indiceA.compareTo(indiceB);
    });

    return <String>['Todos', ...resultado];
  }

  List<String> get tiposDisponibles {
    final List<String> resultado =
        registros
            .map((registro) => registro['tipo'].toString())
            .toSet()
            .toList()
          ..sort();

    return <String>['Todos', ...resultado];
  }

  // =============================================================
  // FILTRADO
  // =============================================================

  List<Map<String, dynamic>> get registrosFiltrados {
    return registros.where((registro) {
      final bool cumpleFecha =
          filtroFecha == 'Todas' || registro['fecha'] == filtroFecha;

      final bool cumpleHorario =
          filtroHorario == 'Todos' || registro['horario'] == filtroHorario;

      final bool cumpleLugar =
          filtroLugar == 'Todos' || registro['lugar'] == filtroLugar;

      final bool cumpleResponsable =
          filtroResponsable == 'Todos' ||
          registro['responsable'] == filtroResponsable;

      final bool cumpleEstado =
          filtroEstado == 'Todos' || registro['estado'] == filtroEstado;

      final bool cumpleTipo =
          filtroTipo == 'Todos' || registro['tipo'] == filtroTipo;

      return cumpleFecha &&
          cumpleHorario &&
          cumpleLugar &&
          cumpleResponsable &&
          cumpleEstado &&
          cumpleTipo;
    }).toList();
  }

  bool get hayFiltrosActivos {
    return filtroFecha != 'Todas' ||
        filtroHorario != 'Todos' ||
        filtroLugar != 'Todos' ||
        filtroResponsable != 'Todos' ||
        filtroEstado != 'Todos' ||
        filtroTipo != 'Todos';
  }

  void limpiarFiltros() {
    setState(() {
      filtroFecha = 'Todas';
      filtroHorario = 'Todos';
      filtroLugar = 'Todos';
      filtroResponsable = 'Todos';
      filtroEstado = 'Todos';
      filtroTipo = 'Todos';
    });
  }

  void _corregirFiltrosSiYaNoExisten() {
    if (!fechasDisponibles.contains(filtroFecha)) {
      filtroFecha = 'Todas';
    }

    if (!horariosDisponibles.contains(filtroHorario)) {
      filtroHorario = 'Todos';
    }

    if (!lugaresDisponibles.contains(filtroLugar)) {
      filtroLugar = 'Todos';
    }

    if (!responsablesDisponibles.contains(filtroResponsable)) {
      filtroResponsable = 'Todos';
    }

    if (!estadosDisponibles.contains(filtroEstado)) {
      filtroEstado = 'Todos';
    }

    if (!tiposDisponibles.contains(filtroTipo)) {
      filtroTipo = 'Todos';
    }
  }

  // =============================================================
  // MOSTRAR FILTROS
  // =============================================================

  void mostrarFiltros() {
    String tempFecha = filtroFecha;
    String tempHorario = filtroHorario;
    String tempLugar = filtroLugar;
    String tempResponsable = filtroResponsable;
    String tempEstado = filtroEstado;
    String tempTipo = filtroTipo;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 45,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD1D5DB),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Filtrar registros',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Puedes combinar varios filtros.',
                        style: TextStyle(color: Color(0xFF6B7280)),
                      ),
                      const SizedBox(height: 24),

                      _FiltroDropdown(
                        titulo: 'Fecha',
                        valor: tempFecha,
                        opciones: fechasDisponibles,
                        onChanged: (valor) {
                          if (valor == null) {
                            return;
                          }

                          setModalState(() {
                            tempFecha = valor;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      _FiltroDropdown(
                        titulo: 'Horario',
                        valor: tempHorario,
                        opciones: horariosDisponibles,
                        onChanged: (valor) {
                          if (valor == null) {
                            return;
                          }

                          setModalState(() {
                            tempHorario = valor;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      _FiltroDropdown(
                        titulo: 'Espacio',
                        valor: tempLugar,
                        opciones: lugaresDisponibles,
                        onChanged: (valor) {
                          if (valor == null) {
                            return;
                          }

                          setModalState(() {
                            tempLugar = valor;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      _FiltroDropdown(
                        titulo: 'Responsable',
                        valor: tempResponsable,
                        opciones: responsablesDisponibles,
                        onChanged: (valor) {
                          if (valor == null) {
                            return;
                          }

                          setModalState(() {
                            tempResponsable = valor;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      _FiltroDropdown(
                        titulo: 'Estado del aseo',
                        valor: tempEstado,
                        opciones: estadosDisponibles,
                        onChanged: (valor) {
                          if (valor == null) {
                            return;
                          }

                          setModalState(() {
                            tempEstado = valor;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      _FiltroDropdown(
                        titulo: 'Tipo de espacio',
                        valor: tempTipo,
                        opciones: tiposDisponibles,
                        onChanged: (valor) {
                          if (valor == null) {
                            return;
                          }

                          setModalState(() {
                            tempTipo = valor;
                          });
                        },
                      ),

                      const SizedBox(height: 28),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              filtroFecha = tempFecha;
                              filtroHorario = tempHorario;
                              filtroLugar = tempLugar;
                              filtroResponsable = tempResponsable;
                              filtroEstado = tempEstado;
                              filtroTipo = tempTipo;
                            });

                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.filter_alt_outlined),
                          label: const Text(
                            'Aplicar filtros',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () {
                            setModalState(() {
                              tempFecha = 'Todas';
                              tempHorario = 'Todos';
                              tempLugar = 'Todos';
                              tempResponsable = 'Todos';
                              tempEstado = 'Todos';
                              tempTipo = 'Todos';
                            });
                          },
                          child: const Text('Limpiar filtros'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // =============================================================
  // ABRIR DETALLE
  // =============================================================

  Future<void> abrirDetalle(Map<String, dynamic> registro) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetalleRegistroSupervisorPage(
          idRegistroAseo: int.tryParse(registro['idRegistroAseo'].toString()),
          fecha: registro['fecha'].toString(),
          responsable: registro['responsable'].toString(),
          lugar: registro['lugar'].toString(),
          inicio: registro['inicio'].toString(),
          termino: registro['termino'].toString(),
          duracion: registro['duracion'].toString(),
          estado: registro['estado'].toString(),
          motivoParcial: registro['motivoParcial']?.toString(),
          categoriaObservacion: registro['categoriaObservacion']?.toString(),
          detalleObservacion: registro['detalleObservacion']?.toString(),
          estadoAlerta: registro['estadoAlerta']?.toString(),
          esCobertura: registro['esCobertura'] == true,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    // Cuando el detalle sea totalmente real, cualquier cambio realizado
    // allí debe reflejarse al regresar. Por eso recargamos desde ya.
    await cargarRegistros();
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
          'Registros de aseo',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: cargando ? null : cargarRegistros,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Labores registradas',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Consulta los registros realizados por los Auxiliares.',
                                  style: TextStyle(color: Color(0xFF6B7280)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: cargando || registros.isEmpty
                                ? null
                                : mostrarFiltros,
                            icon: const Icon(Icons.filter_alt_outlined),
                            label: const Text('Filtrar'),
                          ),
                        ],
                      ),

                      if (hayFiltrosActivos) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.filter_alt,
                                size: 17,
                                color: Color(0xFF1565C0),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Filtros activos',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1565C0),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: limpiarFiltros,
                                child: const Icon(
                                  Icons.close,
                                  size: 17,
                                  color: Color(0xFF1565C0),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 10),

                      if (!cargando && mensajeError == null)
                        Text(
                          '${lista.length} ${lista.length == 1 ? 'registro encontrado' : 'registros encontrados'}',
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
                      ? _ErrorRegistros(
                          mensaje: mensajeError!,
                          onReintentar: cargarRegistros,
                        )
                      : lista.isEmpty
                      ? _SinResultados(hayFiltrosActivos: hayFiltrosActivos)
                      : RefreshIndicator(
                          onRefresh: cargarRegistros,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                            itemCount: lista.length,
                            itemBuilder: (context, index) {
                              final Map<String, dynamic> registro =
                                  lista[index];

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _TarjetaRegistroSupervisor(
                                  registro: registro,
                                  onTap: () {
                                    abrirDetalle(registro);
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
// TARJETA DE REGISTRO
// =================================================================

class _TarjetaRegistroSupervisor extends StatelessWidget {
  final Map<String, dynamic> registro;
  final VoidCallback onTap;

  const _TarjetaRegistroSupervisor({
    required this.registro,
    required this.onTap,
  });

  Color obtenerColorEstado() {
    switch (registro['estado']) {
      case 'Completo':
        return const Color(0xFF16A34A);

      case 'Parcial':
        return const Color(0xFFD97706);

      case 'Con Observaciones':
        return const Color(0xFFDC2626);

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

      default:
        return const Color(0xFFF3F4F6);
    }
  }

  Color obtenerColorObservacion(String estado) {
    switch (estado) {
      case 'Atendida':
      case 'Resuelta':
        return const Color(0xFF16A34A);

      case 'Leída':
      case 'En atención':
        return const Color(0xFFD97706);

      case 'Pendiente':
        return const Color(0xFFDC2626);

      default:
        return const Color(0xFF6B7280);
    }
  }

  Color obtenerFondoObservacion(String estado) {
    switch (estado) {
      case 'Atendida':
      case 'Resuelta':
        return const Color(0xFFF0FDF4);

      case 'Leída':
      case 'En atención':
        return const Color(0xFFFFFBEB);

      case 'Pendiente':
        return const Color(0xFFFEF2F2);

      default:
        return const Color(0xFFF3F4F6);
    }
  }

  IconData obtenerIconoObservacion(String estado) {
    switch (estado) {
      case 'Atendida':
      case 'Resuelta':
        return Icons.check_circle_outline;

      case 'Leída':
        return Icons.mark_email_read_outlined;

      case 'En atención':
        return Icons.pending_actions_outlined;

      case 'Pendiente':
        return Icons.warning_amber_rounded;

      default:
        return Icons.info_outline;
    }
  }

  String obtenerTextoObservacion(String estado) {
    switch (estado) {
      case 'Atendida':
        return 'Observación atendida';

      case 'Resuelta':
        return 'Observación resuelta';

      case 'Leída':
        return 'Observación leída';

      case 'En atención':
        return 'Observación en atención';

      case 'Pendiente':
        return 'Observación pendiente';

      default:
        return 'Observación: $estado';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color colorEstado = obtenerColorEstado();

    final String? estadoObservacion = registro['estadoAlerta']
        ?.toString()
        .trim();

    final bool mostrarEstadoObservacion =
        registro['estado'] == 'Con Observaciones' &&
        estadoObservacion != null &&
        estadoObservacion.isNotEmpty;

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
              Row(
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: obtenerFondoEstado(),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      registro['estado'].toString(),
                      style: TextStyle(
                        color: colorEstado,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: Color(0xFF1565C0),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      registro['lugar'].toString(),
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

              const SizedBox(height: 6),

              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(
                  registro['tipo'].toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),

              const SizedBox(height: 12),

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
                      registro['responsable'].toString(),
                      style: const TextStyle(color: Color(0xFF4B5563)),
                    ),
                  ),
                ],
              ),

              if (registro['esCobertura'] == true) ...[
                const SizedBox(height: 12),
                const Text(
                  'Labor realizada por Auxiliar no asignado',
                  style: TextStyle(
                    color: Color(0xFF92400E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

              if (mostrarEstadoObservacion) ...[
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: obtenerFondoObservacion(estadoObservacion),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        obtenerIconoObservacion(estadoObservacion),
                        size: 16,
                        color: obtenerColorObservacion(estadoObservacion),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        obtenerTextoObservacion(estadoObservacion),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: obtenerColorObservacion(estadoObservacion),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _DatoRegistroSupervisor(
                      titulo: 'Inicio',
                      valor: registro['inicio'].toString(),
                    ),
                  ),
                  Expanded(
                    child: _DatoRegistroSupervisor(
                      titulo: 'Término',
                      valor: registro['termino'].toString(),
                    ),
                  ),
                  Expanded(
                    child: _DatoRegistroSupervisor(
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
// DATO DE LA TARJETA
// =================================================================

class _DatoRegistroSupervisor extends StatelessWidget {
  final String titulo;
  final String valor;

  const _DatoRegistroSupervisor({required this.titulo, required this.valor});

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
// DROPDOWN DE FILTRO
// =================================================================

class _FiltroDropdown extends StatelessWidget {
  final String titulo;
  final String valor;
  final List<String> opciones;
  final ValueChanged<String?> onChanged;

  const _FiltroDropdown({
    required this.titulo,
    required this.valor,
    required this.opciones,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: valor,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: titulo,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: opciones.map((opcion) {
        return DropdownMenuItem<String>(
          value: opcion,
          child: Text(opcion, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}

// =================================================================
// ERROR
// =================================================================

class _ErrorRegistros extends StatelessWidget {
  final String mensaje;
  final Future<void> Function() onReintentar;

  const _ErrorRegistros({required this.mensaje, required this.onReintentar});

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
// SIN RESULTADOS
// =================================================================

class _SinResultados extends StatelessWidget {
  final bool hayFiltrosActivos;

  const _SinResultados({required this.hayFiltrosActivos});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hayFiltrosActivos
                  ? Icons.search_off
                  : Icons.receipt_long_outlined,
              size: 52,
              color: const Color(0xFF9CA3AF),
            ),
            const SizedBox(height: 14),
            Text(
              hayFiltrosActivos
                  ? 'No se encontraron registros'
                  : 'Aún no hay registros finalizados',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4B5563),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hayFiltrosActivos
                  ? 'Prueba modificando los filtros seleccionados.'
                  : 'Cuando los Auxiliares finalicen labores, aparecerán aquí.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
