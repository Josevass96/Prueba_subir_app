import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'detalle_incidencia_mantencion_page.dart';
import 'detalle_registro_supervisor_page.dart';

/// Bandeja personal de notificaciones por observaciones.
/// La tabla public.notificacion y la RPC marcar_notificacion_leida
/// se crean en la etapa 9A de RegiServ.
class NotificacionesPage extends StatefulWidget {
  const NotificacionesPage({super.key});

  @override
  State<NotificacionesPage> createState() => _NotificacionesPageState();
}

class _NotificacionesPageState extends State<NotificacionesPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  Stream<List<Map<String, dynamic>>>? _notificaciones;
  bool _soloSinLeer = false;
  int? _abriendoId;

  @override
  void initState() {
    super.initState();
    final String? idUsuario = supabase.auth.currentUser?.id;
    if (idUsuario != null) {
      // Se crea una sola vez; no se reconecta por cada build.
      _notificaciones = supabase
          .from('notificacion')
          .stream(primaryKey: <String>['id_notificacion'])
          .eq('id_usuario_destino', idUsuario)
          .order('fecha_creacion', ascending: false);
    }
  }

  String _texto(dynamic valor, {String defecto = '—'}) {
    final String texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? defecto : texto;
  }

  int? _entero(dynamic valor) => int.tryParse(valor?.toString() ?? '');

  DateTime? _fecha(dynamic valor) {
    if (valor == null) return null;
    return DateTime.tryParse(valor.toString())?.toLocal();
  }

  String _formatearFecha(dynamic valor) {
    final DateTime? fecha = _fecha(valor);
    if (fecha == null) return 'Fecha no disponible';
    final String dia = fecha.day.toString().padLeft(2, '0');
    final String mes = fecha.month.toString().padLeft(2, '0');
    final String hora = fecha.hour.toString().padLeft(2, '0');
    final String minuto = fecha.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year} · $hora:$minuto';
  }

  String _hora(dynamic valor) {
    final DateTime? fecha = _fecha(valor);
    if (fecha == null) return '-';
    return '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }

  String _duracion(dynamic inicio, dynamic fin) {
    final DateTime? desde = _fecha(inicio);
    final DateTime? hasta = _fecha(fin);
    if (desde == null || hasta == null) return '-';
    final Duration diferencia = hasta.difference(desde);
    if (diferencia.isNegative) return '-';
    if (diferencia.inMinutes < 1) return '< 1 min';
    final int horas = diferencia.inHours;
    final int minutos = diferencia.inMinutes.remainder(60);
    if (horas == 0) return '${diferencia.inMinutes} min';
    if (minutos == 0) return '$horas h';
    return '$horas h $minutos min';
  }

  void _mensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _abrir(Map<String, dynamic> notificacion) async {
    final int? idNotificacion = _entero(notificacion['id_notificacion']);
    if (idNotificacion == null || _abriendoId != null) return;

    setState(() => _abriendoId = idNotificacion);

    try {
      if (notificacion['leida'] != true) {
        final dynamic marcada = await supabase.rpc(
          'marcar_notificacion_leida',
          params: <String, dynamic>{'p_id_notificacion': idNotificacion},
        );
        if (marcada != true) {
          throw Exception('No se pudo marcar la notificación como leída.');
        }
      }

      if (!mounted) return;

      if (notificacion['tipo'] == 'incidencia_mantencion') {
        final int? idAlerta = _entero(notificacion['id_alerta']);
        if (idAlerta == null) {
          _mensaje('No se encontró la incidencia asociada.');
          return;
        }

        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (context) =>
                DetalleIncidenciaMantencionPage(idAlerta: idAlerta),
          ),
        );
      } else {
        final int? idRegistro = _entero(notificacion['id_registro_aseo']);
        if (idRegistro == null) {
          _mensaje('No se encontró el registro asociado.');
          return;
        }

        // Aprovecha la RPC existente de Supervisión para proporcionar
        // los datos del encabezado al detalle real del registro.
        final dynamic respuesta = await supabase.rpc(
          'listar_alertas_supervision',
        );
        if (respuesta is! List) {
          throw Exception('No fue posible consultar las alertas.');
        }

        Map<String, dynamic>? alerta;
        for (final dynamic fila in respuesta) {
          if (fila is! Map) continue;
          if (_entero(fila['id_registro_aseo']) == idRegistro &&
              _entero(fila['id_observacion']) ==
                  _entero(notificacion['id_observacion'])) {
            alerta = Map<String, dynamic>.from(fila);
            break;
          }
        }

        if (alerta == null) {
          _mensaje('El registro ya no está disponible en Supervisión.');
          return;
        }

        if (!mounted) return;
        final Map<String, dynamic> datosAlerta = alerta;
        final String codigo = _texto(
          datosAlerta['espacio_codigo'],
          defecto: 'Sin código',
        );
        final String lugar = _texto(
          datosAlerta['espacio_nombre'],
          defecto: codigo,
        );
        final DateTime? fecha = _fecha(datosAlerta['fecha_alerta']);
        final String fechaTexto = fecha == null
            ? '-'
            : '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (context) => DetalleRegistroSupervisorPage(
              idRegistroAseo: idRegistro,
              fecha: fechaTexto,
              responsable: _texto(
                datosAlerta['responsable'],
                defecto: 'Sin responsable',
              ),
              lugar: lugar,
              inicio: _hora(datosAlerta['fecha_hora_inicio']),
              termino: _hora(datosAlerta['fecha_hora_fin']),
              duracion: _duracion(
                datosAlerta['fecha_hora_inicio'],
                datosAlerta['fecha_hora_fin'],
              ),
              estado: 'Con Observaciones',
              categoriaObservacion: _texto(
                datosAlerta['categoria_observacion'],
                defecto: 'Sin categoría',
              ),
              detalleObservacion: _texto(
                datosAlerta['detalle_observacion'],
                defecto: 'Sin detalle',
              ),
              estadoAlerta: _texto(
                datosAlerta['estado_alerta'],
                defecto: 'Pendiente',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      debugPrint('ERROR abrir notificación RegiServ: $error');
      _mensaje('No fue posible abrir la notificación.');
    } finally {
      if (mounted) {
        setState(() => _abriendoId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Notificaciones'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: SafeArea(
        child: _notificaciones == null
            ? const Center(child: Text('Debes iniciar sesión.'))
            : StreamBuilder<List<Map<String, dynamic>>>(
                stream: _notificaciones,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No fue posible cargar las notificaciones. '
                          'Comprueba la conexión e inténtalo de nuevo.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final List<Map<String, dynamic>> todas = snapshot.data!;
                  final int sinLeer = todas
                      .where((item) => item['leida'] != true)
                      .length;
                  final List<Map<String, dynamic>> visibles = _soloSinLeer
                      ? todas.where((item) => item['leida'] != true).toList()
                      : todas;

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '$sinLeer sin leer',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                FilterChip(
                                  label: const Text('Solo sin leer'),
                                  selected: _soloSinLeer,
                                  onSelected: (seleccionado) {
                                    setState(() => _soloSinLeer = seleccionado);
                                  },
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: visibles.isEmpty
                                ? Center(
                                    child: Text(
                                      _soloSinLeer
                                          ? 'No tienes notificaciones sin leer.'
                                          : 'Todavía no tienes notificaciones.\n'
                                                'Aparecerán al registrarse nuevas observaciones.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      4,
                                      20,
                                      28,
                                    ),
                                    itemCount: visibles.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final Map<String, dynamic> notificacion =
                                          visibles[index];
                                      final bool leida =
                                          notificacion['leida'] == true;
                                      final bool esMantencion =
                                          notificacion['tipo'] ==
                                          'incidencia_mantencion';
                                      final int? id = _entero(
                                        notificacion['id_notificacion'],
                                      );
                                      final bool abriendo = _abriendoId != null;

                                      return Card(
                                        color: leida
                                            ? Colors.white
                                            : const Color(0xFFEFF6FF),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFFE5E7EB),
                                          ),
                                        ),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          onTap: abriendo
                                              ? null
                                              : () => _abrir(notificacion),
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  esMantencion
                                                      ? Icons
                                                            .construction_outlined
                                                      : Icons
                                                            .description_outlined,
                                                  color: const Color(
                                                    0xFF1565C0,
                                                  ),
                                                  size: 26,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        _texto(
                                                          notificacion['titulo'],
                                                        ),
                                                        style: TextStyle(
                                                          fontWeight: leida
                                                              ? FontWeight.w600
                                                              : FontWeight.bold,
                                                          fontSize: 15,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 5),
                                                      Text(
                                                        _texto(
                                                          notificacion['mensaje'],
                                                        ),
                                                        style: const TextStyle(
                                                          height: 1.35,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 9),
                                                      Text(
                                                        _formatearFecha(
                                                          notificacion['fecha_creacion'],
                                                        ),
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Color(
                                                            0xFF6B7280,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (id == _abriendoId)
                                                  const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                else if (!leida)
                                                  const Icon(
                                                    Icons.circle,
                                                    color: Color(0xFF1565C0),
                                                    size: 10,
                                                  )
                                                else
                                                  const Icon(
                                                    Icons.chevron_right,
                                                    color: Color(0xFF9CA3AF),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// Campana reutilizable por Supervisor, Supervisor Jefe y Mantención.
class CampanaNotificaciones extends StatefulWidget {
  const CampanaNotificaciones({super.key});

  @override
  State<CampanaNotificaciones> createState() => _CampanaNotificacionesState();
}

class _CampanaNotificacionesState extends State<CampanaNotificaciones> {
  Stream<List<Map<String, dynamic>>>? _notificaciones;

  @override
  void initState() {
    super.initState();
    final String? idUsuario = Supabase.instance.client.auth.currentUser?.id;
    if (idUsuario != null) {
      _notificaciones = Supabase.instance.client
          .from('notificacion')
          .stream(primaryKey: <String>['id_notificacion'])
          .eq('id_usuario_destino', idUsuario)
          .order('fecha_creacion', ascending: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _notificaciones,
      builder: (context, snapshot) {
        final int pendientes =
            snapshot.data
                ?.where((notificacion) => notificacion['leida'] != true)
                .length ??
            0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Notificaciones',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => const NotificacionesPage(),
                  ),
                );
              },
            ),
            if (pendientes > 0)
              Positioned(
                top: 2,
                right: 2,
                child: IgnorePointer(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      pendientes > 99 ? '99+' : '$pendientes',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
