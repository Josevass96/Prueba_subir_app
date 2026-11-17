import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/sesion_data.dart';
import 'gestion_usuarios_page.dart';
import 'gestion_sectores_page.dart';
import 'gestion_asignaciones_page.dart';
import 'registros_supervisor_page.dart';
import 'alertas_supervisor_page.dart';
import 'solicitudes_excepciones_supervisor_page.dart';
import 'marcar_nfc_danado_page.dart';
import 'reportes_web_supervisor_jefe_page.dart';

// REGISERV - PANEL WEB EXCLUSIVO PARA SUPERVISOR JEFE
// Etapa WEB-03: acceso por rol, indicadores y sección de reportes PDF/Excel.
// Las autorizaciones definitivas las aplican las políticas RLS y RPC
// de Supabase; los controles de Flutter son una protección adicional.

class _BarraPeriodo {
  final String etiqueta;
  int total = 0;
  int coberturas = 0;

  _BarraPeriodo(this.etiqueta);
}

class PanelWebSupervisorJefePage extends StatefulWidget {
  const PanelWebSupervisorJefePage({super.key});

  @override
  State<PanelWebSupervisorJefePage> createState() =>
      _PanelWebSupervisorJefePageState();
}

class _PanelWebSupervisorJefePageState
    extends State<PanelWebSupervisorJefePage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  StreamSubscription<AuthState>? _authSubscription;

  bool _verificando = true;
  bool _autorizado = false;
  bool _cargandoResumen = false;
  bool _cerrandoSesion = false;
  String? _errorAcceso;
  String? _errorResumen;

  int _laboresHoy = 0;
  int _laboresPeriodo = 0;
  int _coberturasPeriodo = 0;
  int _diasPeriodo = 30;
  int _versionConsulta = 0;
  DateTime? _ultimaActualizacion;
  List<_BarraPeriodo> _barras = <_BarraPeriodo>[];
  int _solicitudesPendientes = 0;
  int _alertasAbiertas = 0;
  int _nfcDanados = 0;

  static const Color _azul = Color(0xFF1565C0);
  static const Color _fondo = Color(0xFFF5F7FA);

  @override
  void initState() {
    super.initState();
    _authSubscription = _supabase.auth.onAuthStateChange.listen(
      (estado) {
        if (estado.event == AuthChangeEvent.signedOut &&
            mounted &&
            !_cerrandoSesion) {
          SesionData.cerrarSesion();
          Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('AVISO AUTH PANEL WEB REGISERV: $error');
      },
    );
    unawaited(_verificarRolYEntrar());
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  int? _numero(dynamic dato) {
    if (dato is int) return dato;
    if (dato is num) return dato.toInt();
    return int.tryParse(dato?.toString() ?? '');
  }

  Future<void> _verificarRolYEntrar() async {
    if (!mounted) return;
    setState(() {
      _verificando = true;
      _errorAcceso = null;
    });

    try {
      final usuarioAuth = _supabase.auth.currentUser;
      if (usuarioAuth == null || _supabase.auth.currentSession == null) {
        if (!mounted) return;
        setState(() {
          _autorizado = false;
          _errorAcceso = 'No hay una sesión iniciada.';
          _verificando = false;
        });
        return;
      }

      final perfil = await _supabase
          .from('usuario')
          .select('id_rol, activo, primer_acceso, requiere_cambio_clave')
          .eq('id_usuario', usuarioAuth.id)
          .single();
      final rol = await _supabase
          .from('rol')
          .select('nombre')
          .eq('id_rol', perfil['id_rol'])
          .single();

      if (!mounted || _supabase.auth.currentUser?.id != usuarioAuth.id) return;
      final permitido =
          perfil['activo'] == true &&
          perfil['primer_acceso'] != true &&
          perfil['requiere_cambio_clave'] != true &&
          rol['nombre'] == 'Supervisor Jefe';
      setState(() {
        _autorizado = permitido;
        _verificando = false;
        _errorAcceso = permitido
            ? null
            : 'Solo el Supervisor Jefe activo puede acceder al panel web.';
      });
      if (permitido) await _cargarResumen();
    } catch (error) {
      debugPrint('ERROR VERIFICANDO SUPERVISOR JEFE WEB: $error');
      if (!mounted) return;
      setState(() {
        _autorizado = false;
        _verificando = false;
        _errorAcceso = 'No fue posible verificar tu permiso. Revisa la conexión e intenta nuevamente.';
      });
    }
  }

  // La consulta se limita al período seleccionado y se pagina para no
  // depender del límite predeterminado de filas de PostgREST.
  // Siempre se usa el usuario autenticado y se aplican las políticas RLS.
  Future<List<Map<String, dynamic>>> _registrosFinalizadosDelPeriodo(
    DateTime desde,
    DateTime hastaExclusivo,
  ) async {
    const int tamanoPagina = 500;
    int inicioPagina = 0;
    final resultado = <Map<String, dynamic>>[];

    while (true) {
      final filas = await _supabase
          .from('registro_aseo')
          .select('id_registro_aseo, fecha_hora_fin, es_cobertura')
          .gte('fecha_hora_fin', desde.toUtc().toIso8601String())
          .lt('fecha_hora_fin', hastaExclusivo.toUtc().toIso8601String())
          .order('fecha_hora_fin', ascending: true)
          .order('id_registro_aseo', ascending: true)
          .range(inicioPagina, inicioPagina + tamanoPagina - 1);

      for (final fila in filas) {
        resultado.add(Map<String, dynamic>.from(fila));
      }
      if (filas.length < tamanoPagina) break;
      inicioPagina += tamanoPagina;
    }
    return resultado;
  }

  int _diferenciaDiasCalendario(DateTime primero, DateTime segundo) {
    return DateTime.utc(
      segundo.year,
      segundo.month,
      segundo.day,
    ).difference(DateTime.utc(primero.year, primero.month, primero.day)).inDays;
  }

  String _fechaBreve(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}';
  }

  // Aún no se ha habilitado un reporte exportable: todas las cifras
  // corresponden a registros reales que retorna Supabase.
  Future<void> _cargarResumen() async {
    if (!mounted || !_autorizado) return;
    final int version = ++_versionConsulta;
    final int dias = _diasPeriodo;
    setState(() {
      _cargandoResumen = true;
      _errorResumen = null;
    });

    try {
      final ahora = DateTime.now();
      final inicio = DateTime(ahora.year, ahora.month, ahora.day - dias + 1);
      final finExclusivo = DateTime(ahora.year, ahora.month, ahora.day + 1);
      final registros = await _registrosFinalizadosDelPeriodo(
        inicio,
        finExclusivo,
      );

      int laboresHoy = 0;
      int coberturasPeriodo = 0;
      final paso = dias == 7
          ? 1
          : dias == 30
          ? 5
          : 10;
      final cantidadBloques = (dias + paso - 1) ~/ paso;
      final barras = List<_BarraPeriodo>.generate(cantidadBloques, (i) {
        final fecha = DateTime(
          inicio.year,
          inicio.month,
          inicio.day + i * paso,
        );
        return _BarraPeriodo(_fechaBreve(fecha));
      });

      for (final registro in registros) {
        final fechaRaw = registro['fecha_hora_fin'];
        final fin = fechaRaw == null
            ? null
            : DateTime.tryParse(fechaRaw.toString())?.toLocal();
        if (fin == null) continue;
        final diferencia = _diferenciaDiasCalendario(inicio, fin);
        if (diferencia < 0 || diferencia >= dias) continue;
        final cobertura = registro['es_cobertura'] == true;
        final bloque = barras[diferencia ~/ paso];
        bloque.total++;
        if (cobertura) {
          bloque.coberturas++;
          coberturasPeriodo++;
        }
        if (fin.year == ahora.year &&
            fin.month == ahora.month &&
            fin.day == ahora.day) {
          laboresHoy++;
        }
      }

      // Estos tres indicadores son globales (estado actual), no forman
      // parte del filtro de días aplicable a las labores finalizadas.
      final alertasRaw = await _supabase.rpc('listar_alertas_supervision');
      final alertas = alertasRaw is List ? alertasRaw : <dynamic>[];
      const estadosAbiertos = <String>{'Pendiente', 'Leída', 'En atención'};
      final alertasAbiertas = alertas.where((fila) {
        return fila is Map &&
            estadosAbiertos.contains((fila['estado_alerta'] ?? '').toString());
      }).length;

      final tiposAlerta = await _supabase
          .from('tipo_alerta')
          .select('id_tipo_alerta, nombre_alerta')
          .eq('activo', true);
      int? idTipoSolicitud;
      for (final tipo in tiposAlerta) {
        if (tipo['nombre_alerta'] == 'Cierre excepcional') {
          idTipoSolicitud = _numero(tipo['id_tipo_alerta']);
          break;
        }
      }
      int solicitudes = 0;
      if (idTipoSolicitud != null) {
        final filas = await _supabase
            .from('alerta')
            .select('id_alerta, estado')
            .eq('id_tipo_alerta', idTipoSolicitud)
            .inFilter('estado', estadosAbiertos.toList());
        solicitudes = filas.length;
      }

      final estadosNfc = await _supabase
          .from('estado_nfc')
          .select('id_estado_nfc')
          .eq('nombre_estado', 'Dañado');
      int danados = 0;
      if (estadosNfc.isNotEmpty) {
        final idEstado = _numero(estadosNfc.first['id_estado_nfc']);
        if (idEstado != null) {
          final filas = await _supabase
              .from('nfc')
              .select('id_nfc')
              .eq('id_estado_nfc', idEstado)
              .isFilter('fecha_retiro', null);
          danados = filas.length;
        }
      }

      if (!mounted || version != _versionConsulta) return;
      setState(() {
        _laboresHoy = laboresHoy;
        _laboresPeriodo = barras.fold<int>(0, (total, b) => total + b.total);
        _coberturasPeriodo = coberturasPeriodo;
        _barras = barras;
        _solicitudesPendientes = solicitudes;
        _alertasAbiertas = alertasAbiertas;
        _nfcDanados = danados;
        _ultimaActualizacion = DateTime.now();
        _cargandoResumen = false;
      });
    } catch (error) {
      debugPrint('ERROR DASHBOARD PANEL WEB REGISERV: $error');
      if (!mounted || version != _versionConsulta) return;
      setState(() {
        _cargandoResumen = false;
        _errorResumen =
            'No se pudo cargar el dashboard desde Supabase. '
            'Revisa la conexión y los permisos de lectura de registro_aseo.';
      });
    }
  }

  void _cambiarPeriodo(int dias) {
    if (dias == _diasPeriodo || _cargandoResumen) return;
    setState(() => _diasPeriodo = dias);
    unawaited(_cargarResumen());
  }

  Future<void> _abrirAdministracion(Widget pagina) async {
    if (!_autorizado || !mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => pagina));
    if (mounted) await _verificarRolYEntrar();
  }

  Future<void> _cerrarSesion() async {
    if (_cerrandoSesion) return;
    setState(() => _cerrandoSesion = true);
    try {
      await _supabase.auth.signOut(scope: SignOutScope.local);
    } catch (error) {
      debugPrint('ERROR CERRAR SESIÓN PANEL WEB: $error');
      if (mounted) {
        setState(() {
          _cerrandoSesion = false;
          _errorAcceso = 'No fue posible cerrar sesión. Intenta nuevamente.';
        });
      }
      return;
    }
    SesionData.cerrarSesion();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  Widget _opcion({
    required IconData icono,
    required String titulo,
    required VoidCallback accion,
    bool seleccionada = false,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(
        icono,
        color: seleccionada ? _azul : const Color(0xFF64748B),
      ),
      selected: seleccionada,
      selectedTileColor: const Color(0xFFE8F0FE),
      title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w500)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: accion,
    );
  }

  Widget _menu() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SizedBox(height: 6),
        const Row(
          children: [
            Icon(Icons.cleaning_services_outlined, size: 29, color: _azul),
            SizedBox(width: 10),
            Text(
              'RegiServ',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 5),
        const Text(
          'Panel web · Supervisor Jefe',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const Divider(height: 34),
        _opcion(
          icono: Icons.dashboard_outlined,
          titulo: 'Resumen',
          seleccionada: true,
          accion: () => unawaited(_cargarResumen()),
        ),
        _opcion(
          icono: Icons.people_outline,
          titulo: 'Usuarios',
          accion: () => _abrirAdministracion(const GestionUsuariosPage()),
        ),
        _opcion(
          icono: Icons.domain_outlined,
          titulo: 'Sectores y espacios',
          accion: () => _abrirAdministracion(const GestionSectoresPage()),
        ),
        _opcion(
          icono: Icons.assignment_ind_outlined,
          titulo: 'Asignaciones',
          accion: () => _abrirAdministracion(const GestionAsignacionesPage()),
        ),
        const Divider(height: 22),
        _opcion(
          icono: Icons.fact_check_outlined,
          titulo: 'Registros de aseo',
          accion: () => _abrirAdministracion(const RegistrosSupervisorPage()),
        ),
        _opcion(
          icono: Icons.notifications_active_outlined,
          titulo: 'Alertas',
          accion: () => _abrirAdministracion(const AlertasSupervisorPage()),
        ),
        _opcion(
          icono: Icons.rule_folder_outlined,
          titulo: 'Cierres excepcionales',
          accion: () => _abrirAdministracion(
            const SolicitudesExcepcionesSupervisorPage(),
          ),
        ),
        _opcion(
          icono: Icons.nfc_outlined,
          titulo: 'NFC dañados',
          accion: () => _abrirAdministracion(const MarcarNfcDanadoPage()),
        ),
        const Divider(height: 22),
        _opcion(
          icono: Icons.description_outlined,
          titulo: 'Reportes PDF / Excel',
          accion: () =>
              _abrirAdministracion(const ReportesWebSupervisorJefePage()),
        ),
        const SizedBox(height: 22),
        OutlinedButton.icon(
          onPressed: _cerrandoSesion ? null : _cerrarSesion,
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
        ),
      ],
    );
  }

  Widget _tarjetaIndicador({
    required String titulo,
    required int valor,
    required IconData icono,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icono, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(titulo, style: const TextStyle(color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                Text(
                  _errorResumen == null ? '$valor' : '—',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectorPeriodo() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 4),
          child: Text(
            'Mostrar:',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        for (final dias in const [7, 30, 90])
          ChoiceChip(
            label: Text('Últimos $dias días'),
            selected: _diasPeriodo == dias,
            onSelected: _cargandoResumen
                ? null
                : (seleccionado) {
                    if (seleccionado) _cambiarPeriodo(dias);
                  },
          ),
      ],
    );
  }

  Widget _leyenda(Color color, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          texto,
          style: const TextStyle(color: Color(0xFF475569), fontSize: 13),
        ),
      ],
    );
  }

  Widget _graficoActividad() {
    final maximo = _barras.fold<int>(1, (m, b) => math.max(m, b.total));
    final vacio = _laboresPeriodo == 0;
    const azul = Color(0xFF2563EB);
    const naranja = Color(0xFFF59E0B);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Evolución de labores finalizadas',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            _diasPeriodo == 7
                ? 'Una columna por día.'
                : 'Datos agrupados cada ${_diasPeriodo == 30 ? 5 : 10} días.',
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _leyenda(azul, 'Labores asignadas'),
              _leyenda(naranja, 'Coberturas'),
            ],
          ),
          const SizedBox(height: 14),
          if (vacio)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 45),
              child: Center(
                child: Text(
                  'No hay labores finalizadas en este período.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, limites) {
                final ancho = math.max(
                  60.0,
                  (limites.maxWidth - 12) / _barras.length,
                );
                return SizedBox(
                  height: 216,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final barra in _barras)
                          SizedBox(
                            width: ancho,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  '${barra.total}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                SizedBox(
                                  height: 148,
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: barra.total == 0
                                        ? const SizedBox.shrink()
                                        : Tooltip(
                                            message:
                                                '${barra.etiqueta}: '
                                                '${barra.total} labores; '
                                                '${barra.coberturas} coberturas',
                                            child: SizedBox(
                                              width: math.min(
                                                36.0,
                                                ancho * 0.54,
                                              ),
                                              height:
                                                  148 * barra.total / maximo,
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                                child: Column(
                                                  children: [
                                                    if (barra.total >
                                                        barra.coberturas)
                                                      Expanded(
                                                        flex:
                                                            barra.total -
                                                            barra.coberturas,
                                                        child: Container(
                                                          color: azul,
                                                        ),
                                                      ),
                                                    if (barra.coberturas > 0)
                                                      Expanded(
                                                        flex: barra.coberturas,
                                                        child: Container(
                                                          color: naranja,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  barra.etiqueta,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 5),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _distribucionLabores() {
    final normales = _laboresPeriodo - _coberturasPeriodo;
    final proporcion = _laboresPeriodo == 0 ? 0.0 : normales / _laboresPeriodo;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Distribución de labores',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Asignadas y realizadas como cobertura durante el período.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(child: Text('Labores asignadas')),
              Text(
                '$normales',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: proporcion,
            minHeight: 14,
            borderRadius: BorderRadius.circular(7),
            color: const Color(0xFF2563EB),
            backgroundColor: const Color(0xFFE2E8F0),
          ),
          const SizedBox(height: 23),
          Row(
            children: [
              const Expanded(child: Text('Coberturas (no asignadas)')),
              Text(
                '$_coberturasPeriodo',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _laboresPeriodo == 0
                ? 0
                : _coberturasPeriodo / _laboresPeriodo,
            minHeight: 14,
            borderRadius: BorderRadius.circular(7),
            color: const Color(0xFFF59E0B),
            backgroundColor: const Color(0xFFE2E8F0),
          ),
          const SizedBox(height: 20),
          Text(
            'Total en el período: $_laboresPeriodo',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (_laboresPeriodo == 0) ...[
            const SizedBox(height: 8),
            const Text(
              'Aún no hay datos para comparar.',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contenido() {
    final nombre = SesionData.primerNombreActual.trim().isNotEmpty
        ? SesionData.primerNombreActual
        : 'Supervisor Jefe';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bienvenido, $nombre',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 5),
        const Text(
          'Dashboard operativo · Duoc UC Sede San Andrés',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),
        _selectorPeriodo(),
        if (_ultimaActualizacion != null) ...[
          const SizedBox(height: 5),
          Text(
            'Datos actualizados: '
            '${_ultimaActualizacion!.day.toString().padLeft(2, '0')}/'
            '${_ultimaActualizacion!.month.toString().padLeft(2, '0')} '
            '${_ultimaActualizacion!.hour.toString().padLeft(2, '0')}:'
            '${_ultimaActualizacion!.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ],
        const SizedBox(height: 22),
        if (_errorResumen != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFB45309)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_errorResumen!)),
                  TextButton(
                    onPressed: _cargarResumen,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, limites) {
            final columnas = limites.maxWidth < 550
                ? 1
                : limites.maxWidth < 900
                ? 2
                : 3;
            return GridView.count(
              crossAxisCount: columnas,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              mainAxisExtent: columnas == 1 ? 124 : 146,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _tarjetaIndicador(
                  titulo: 'Labores finalizadas hoy',
                  valor: _laboresHoy,
                  icono: Icons.task_alt,
                  color: _azul,
                ),
                _tarjetaIndicador(
                  titulo: 'Labores finalizadas · $_diasPeriodo días',
                  valor: _laboresPeriodo,
                  icono: Icons.calendar_month_outlined,
                  color: _azul,
                ),
                _tarjetaIndicador(
                  titulo: 'Coberturas · $_diasPeriodo días',
                  valor: _coberturasPeriodo,
                  icono: Icons.swap_horiz,
                  color: const Color(0xFFF59E0B),
                ),
                _tarjetaIndicador(
                  titulo: 'Alertas abiertas (actual)',
                  valor: _alertasAbiertas,
                  icono: Icons.notifications_active_outlined,
                  color: const Color(0xFFDC2626),
                ),
                _tarjetaIndicador(
                  titulo: 'Cierres excepcionales pendientes (actual)',
                  valor: _solicitudesPendientes,
                  icono: Icons.pending_actions,
                  color: const Color(0xFFCA8A04),
                ),
                _tarjetaIndicador(
                  titulo: 'Etiquetas NFC dañadas (actual)',
                  valor: _nfcDanados,
                  icono: Icons.nfc,
                  color: const Color(0xFF7C3AED),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, limites) {
            if (limites.maxWidth < 960) {
              return Column(
                children: [
                  _graficoActividad(),
                  const SizedBox(height: 14),
                  _distribucionLabores(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _graficoActividad()),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _distribucionLabores()),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Panel administrativo',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Usa el menú para gestionar usuarios, edificios, pisos, sectores, '
                'asignaciones, registros y alertas. Los gráficos consultan '
                'datos reales de Supabase.',
              ),
              SizedBox(height: 10),
              Text(
                'Las cifras de labores se filtran por período; '
                'alertas, cierres excepcionales y NFC dañados reflejan '
                'su estado actual. Los reportes PDF/Excel siguen pendientes.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_verificando) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 15),
              Text('Verificando acceso al panel web...'),
            ],
          ),
        ),
      );
    }
    if (!_autorizado) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.admin_panel_settings_outlined,
                    color: _azul,
                    size: 48,
                  ),
                  const SizedBox(height: 15),
                  Text(
                    _errorAcceso ?? 'Acceso restringido.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _verificarRolYEntrar,
                    child: const Text('Reintentar'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _cerrandoSesion ? null : _cerrarSesion,
                    child: const Text('Volver al inicio'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, limites) {
        final escritorio = limites.maxWidth >= 930;
        final contenido = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Panel Supervisor Jefe',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                if (_cargandoResumen)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                IconButton(
                  onPressed: _cargandoResumen ? null : _verificarRolYEntrar,
                  icon: const Icon(Icons.refresh_outlined),
                  tooltip: 'Actualizar resumen y permisos',
                ),
              ],
            ),
            const SizedBox(height: 22),
            _contenido(),
          ],
        );
        return Scaffold(
          backgroundColor: _fondo,
          appBar: escritorio
              ? null
              : AppBar(title: const Text('RegiServ · Administración')),
          drawer: escritorio ? null : Drawer(child: _menu()),
          body: SafeArea(
            child: Row(
              children: [
                if (escritorio)
                  Container(
                    width: 265,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        right: BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    child: _menu(),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(escritorio ? 32 : 18),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1300),
                      child: contenido,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
