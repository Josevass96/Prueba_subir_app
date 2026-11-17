import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

/// REGISERV WEB-03 - REPORTES EXCLUSIVOS DEL SUPERVISOR JEFE.
///
/// Sin SQL nuevo: consulta las RPC existentes de supervisión y la marca de
/// cobertura en registro_aseo. La seguridad definitiva depende de Supabase.
/// No entrega registros parciales como si fueran reportes completos.
class ReportesWebSupervisorJefePage extends StatefulWidget {
  const ReportesWebSupervisorJefePage({super.key});

  @override
  State<ReportesWebSupervisorJefePage> createState() =>
      _ReportesWebSupervisorJefePageState();
}

class _FilaReporte {
  final String id;
  final DateTime? fecha;
  final String responsable;
  final String espacio;
  final String estado;
  final String categoria;
  final String inicio;
  final String termino;
  final String detalle;
  final String sincronizacion;

  const _FilaReporte({
    required this.id,
    required this.fecha,
    required this.responsable,
    required this.espacio,
    required this.estado,
    required this.categoria,
    required this.inicio,
    required this.termino,
    required this.detalle,
    required this.sincronizacion,
  });
}

class _ReportesWebSupervisorJefePageState
    extends State<ReportesWebSupervisorJefePage> {
  final SupabaseClient _sb = Supabase.instance.client;
  static const int _tamanoPagina = 400;
  static const int _maximoRegistros = 2000;
  static const int _maximoPdf = 650;

  late DateTime _desde;
  late DateTime _hasta;
  String _tipoReporte = 'labores';
  String _responsable = 'Todos';
  String _espacio = 'Todos';
  String _estado = 'Todos';
  String _categoria = 'Todos';
  bool _verificando = true;
  bool _autorizado = false;
  bool _cargando = false;
  bool _exportando = false;
  bool _incompleto = false;
  String? _error;
  String? _errorAcceso;
  DateTime? _fechaConsulta;
  List<_FilaReporte> _filas = [];
  int _versionConsulta = 0;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _hasta = DateTime(hoy.year, hoy.month, hoy.day);
    _desde = DateTime(hoy.year, hoy.month, hoy.day - 29);
    _verificarRol();
  }

  String _texto(dynamic valor, [String defecto = '-']) {
    final texto = (valor ?? '').toString().trim();
    return texto.isEmpty ? defecto : texto;
  }

  DateTime? _fecha(dynamic valor) {
    if (valor == null) return null;
    return DateTime.tryParse(valor.toString())?.toLocal();
  }

  String _fechaTexto(DateTime? valor, {bool hora = false}) {
    if (valor == null) return '-';
    final d = valor.day.toString().padLeft(2, '0');
    final m = valor.month.toString().padLeft(2, '0');
    final f = '$d/$m/${valor.year}';
    if (!hora) return f;
    return '$f ${valor.hour.toString().padLeft(2, '0')}:'
        '${valor.minute.toString().padLeft(2, '0')}';
  }

  String _codigoFecha(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  String get _nombreReporte {
    switch (_tipoReporte) {
      case 'alertas':
        return 'Alertas y observaciones';
      case 'mantencion':
        return 'Incidencias derivadas a Mantención';
      default:
        return 'Labores de aseo';
    }
  }

  Future<void> _verificarRol() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null || _sb.auth.currentSession == null) {
        throw StateError('No hay una sesión iniciada.');
      }
      final perfil = await _sb
          .from('usuario')
          .select('id_rol, activo, primer_acceso, requiere_cambio_clave')
          .eq('id_usuario', uid)
          .single();
      final rol = await _sb
          .from('rol')
          .select('nombre')
          .eq('id_rol', perfil['id_rol'])
          .single();
      final permitido = _sb.auth.currentUser?.id == uid &&
          perfil['activo'] == true &&
          perfil['primer_acceso'] != true &&
          perfil['requiere_cambio_clave'] != true &&
          rol['nombre'] == 'Supervisor Jefe';
      if (!mounted) return;
      setState(() {
        _verificando = false;
        _autorizado = permitido;
        _errorAcceso = permitido ? null : 'Acceso exclusivo del Supervisor Jefe.';
      });
      if (permitido) await _cargar();
    } catch (e) {
      debugPrint('ERROR ACCESO REPORTES WEB: $e');
      if (!mounted) return;
      setState(() {
        _verificando = false;
        _autorizado = false;
        _errorAcceso = 'No se pudo validar el acceso al módulo de reportes.';
      });
    }
  }

  Future<void> _elegirFecha({required bool inicial}) async {
    final actual = inicial ? _desde : _hasta;
    final elegida = await showDatePicker(
      context: context,
      initialDate: actual,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: inicial ? 'Desde' : 'Hasta',
    );
    if (elegida == null || !mounted) return;
    setState(() {
      if (inicial) {
        _desde = elegida;
      } else {
        _hasta = elegida;
      }
      _filas = [];
      _fechaConsulta = null;
      _error = null;
      _incompleto = false;
      _responsable = 'Todos';
      _espacio = 'Todos';
      _estado = 'Todos';
      _categoria = 'Todos';
    });
  }

  // Funciones setof(table): se aplican filtros y paginación en PostgREST.
  // Se pide una fila extra para detectar un resultado que superaría el límite.
  Future<List<Map<String, dynamic>>> _consultarRpcPaginada(
    String nombre,
    String campoFecha,
    DateTime desde,
    DateTime finExclusivo,
  ) async {
    final registros = <Map<String, dynamic>>[];
    var desplazamiento = 0;
    while (true) {
      final respuesta = await _sb
          .rpc(nombre)
          .gte(campoFecha, desde.toUtc().toIso8601String())
          .lt(campoFecha, finExclusivo.toUtc().toIso8601String())
          .order(campoFecha, ascending: false)
          .range(desplazamiento, desplazamiento + _tamanoPagina - 1);
      if (respuesta is! List) {
        throw StateError('Respuesta inesperada al consultar $nombre.');
      }
      for (final fila in respuesta) {
        if (fila is Map) {
          registros.add(Map<String, dynamic>.from(fila));
        }
      }
      if (registros.length > _maximoRegistros) break;
      if (respuesta.length < _tamanoPagina) break;
      desplazamiento += _tamanoPagina;
    }
    return registros;
  }

  // La RPC de supervisión aún no expone es_cobertura. Se obtiene de la tabla
  // real sin modificar la función usada por las pantallas Android.
  Future<Map<String, bool>> _coberturasDeRegistros(
    List<Map<String, dynamic>> registros,
  ) async {
    final ids = registros
        .map((r) => r['id_registro_aseo'])
        .where((v) => v != null)
        .toList();
    final resultado = <String, bool>{};
    for (var inicio = 0; inicio < ids.length; inicio += 200) {
      final fin = (inicio + 200 < ids.length) ? inicio + 200 : ids.length;
      final respuesta = await _sb
          .from('registro_aseo')
          .select('id_registro_aseo, es_cobertura')
          .inFilter('id_registro_aseo', ids.sublist(inicio, fin));
      for (final fila in respuesta) {
        resultado[_texto(fila['id_registro_aseo'])] =
            fila['es_cobertura'] == true;
      }
    }
    // Si una fila no tiene permiso de lectura, no la clasificamos como normal.
    if (resultado.length != ids.toSet().length) {
      throw StateError('No fue posible consultar la cobertura de todos los registros.');
    }
    return resultado;
  }

  Future<Set<String>> _categoriasMantencion() async {
    final tipos = await _sb
        .from('tipo_observacion')
        .select('nombre, deriva_mantencion')
        .eq('deriva_mantencion', true);
    return tipos.map((t) => _texto(t['nombre'])).toSet();
  }

  Future<void> _cargar() async {
    if (!_autorizado || _cargando) return;
    if (_desde.isAfter(_hasta)) {
      setState(() => _error = 'La fecha inicial no puede ser posterior a la final.');
      return;
    }
    final dias = DateTime.utc(_hasta.year, _hasta.month, _hasta.day)
        .difference(DateTime.utc(_desde.year, _desde.month, _desde.day))
        .inDays;
    if (dias > 365) {
      setState(() => _error = 'Selecciona un período de 366 días como máximo.');
      return;
    }
    final version = ++_versionConsulta;
    setState(() {
      _cargando = true;
      _error = null;
      _incompleto = false;
      _filas = [];
      _responsable = 'Todos';
      _espacio = 'Todos';
      _estado = 'Todos';
      _categoria = 'Todos';
    });
    try {
      final d = DateTime(_desde.year, _desde.month, _desde.day);
      final f = DateTime(_hasta.year, _hasta.month, _hasta.day + 1);
      List<_FilaReporte> nuevas;
      var truncado = false;
      if (_tipoReporte == 'labores') {
        final datos = await _consultarRpcPaginada(
          'listar_registros_supervision', 'fecha_hora_fin', d, f,
        );
        truncado = datos.length > _maximoRegistros;
        // No generamos un reporte parcial ni etiquetamos resultados truncados.
        if (truncado) {
          nuevas = [];
        } else {
          final coberturas = await _coberturasDeRegistros(datos);
          nuevas = datos.map((r) {
            final id = _texto(r['id_registro_aseo']);
            final cobertura = coberturas[id] == true;
            final codigo = _texto(r['espacio_codigo'], '');
            final nombre = _texto(r['espacio_nombre'], '');
            return _FilaReporte(
              id: id,
              fecha: _fecha(r['fecha_hora_fin']),
              responsable: _texto(r['responsable']),
              espacio: '$codigo ${nombre.isEmpty ? '' : '- $nombre'}'.trim(),
              estado: _texto(r['estado_aseo']),
              categoria: cobertura ? 'Cobertura' : 'Asignada',
              inicio: _fechaTexto(_fecha(r['fecha_hora_inicio']), hora: true),
              termino: _fechaTexto(_fecha(r['fecha_hora_fin']), hora: true),
              detalle: _texto(r['detalle_observacion']),
              sincronizacion: _texto(r['estado_sincronizacion']),
            );
          }).toList();
        }
      } else {
        final datos = await _consultarRpcPaginada(
          'listar_alertas_supervision', 'fecha_alerta', d, f,
        );
        truncado = datos.length > _maximoRegistros;
        if (truncado) {
          nuevas = [];
        } else {
          Set<String>? categorias;
          if (_tipoReporte == 'mantencion') {
            categorias = await _categoriasMantencion();
          }
          nuevas = datos.where((r) {
            return categorias == null ||
                categorias.contains(_texto(r['categoria_observacion']));
          }).map((r) {
            final codigo = _texto(r['espacio_codigo'], '');
            final nombre = _texto(r['espacio_nombre'], '');
            return _FilaReporte(
              id: _texto(r['id_alerta'], 'Obs. ${_texto(r['id_observacion'])}'),
              fecha: _fecha(r['fecha_alerta']),
              responsable: _texto(r['responsable']),
              espacio: '$codigo ${nombre.isEmpty ? '' : '- $nombre'}'.trim(),
              estado: _texto(r['estado_alerta']),
              categoria: _texto(r['categoria_observacion']),
              inicio: _fechaTexto(_fecha(r['fecha_hora_inicio']), hora: true),
              termino: _fechaTexto(_fecha(r['fecha_hora_fin']), hora: true),
              detalle: _texto(r['detalle_observacion']),
              sincronizacion: '-',
            );
          }).toList();
        }
      }
      if (!mounted || version != _versionConsulta) return;
      setState(() {
        _filas = nuevas;
        _incompleto = truncado;
        _fechaConsulta = DateTime.now();
        _cargando = false;
        if (truncado) {
          _error = 'Hay más de $_maximoRegistros registros en el período. '
              'Acota las fechas para obtener un reporte completo.';
        }
      });
    } catch (e, stack) {
      debugPrint('ERROR REPORTE REGISERV: $e\n$stack');
      if (!mounted || version != _versionConsulta) return;
      setState(() {
        _cargando = false;
        _filas = [];
        _error = 'No fue posible consultar el reporte completo. '
            'Comprueba la conexión, las RPC y los permisos de Supabase.';
      });
    }
  }

  List<String> _opciones(String Function(_FilaReporte) selector) {
    final valores = _filas.map(selector).where((s) => s.trim().isNotEmpty).toSet()
      .toList()..sort();
    return ['Todos', ...valores];
  }

  List<_FilaReporte> get _filtradas => _filas.where((fila) {
    return (_responsable == 'Todos' || fila.responsable == _responsable) &&
        (_espacio == 'Todos' || fila.espacio == _espacio) &&
        (_estado == 'Todos' || fila.estado == _estado) &&
        (_categoria == 'Todos' || fila.categoria == _categoria);
  }).toList();

  List<String> get _encabezados => _tipoReporte == 'labores'
      ? [
          'ID registro', 'Fecha término', 'Auxiliar', 'Espacio',
          'Tipo de ejecución', 'Estado labor', 'Inicio', 'Término',
          'Observación', 'Sincronización',
        ]
      : [
          'ID alerta', 'Fecha alerta', 'Responsable', 'Espacio',
          'Categoría', 'Estado alerta', 'Detalle', 'Inicio labor', 'Término labor',
        ];

  List<String> _valores(_FilaReporte f) => _tipoReporte == 'labores'
      ? [
          f.id, _fechaTexto(f.fecha, hora: true), f.responsable, f.espacio,
          f.categoria, f.estado, f.inicio, f.termino, f.detalle, f.sincronizacion,
        ]
      : [
          f.id, _fechaTexto(f.fecha, hora: true), f.responsable, f.espacio,
          f.categoria, f.estado, f.detalle, f.inicio, f.termino,
        ];

  String get _resumenFiltros =>
      'Período: ${_fechaTexto(_desde)} - ${_fechaTexto(_hasta)} | '
      'Responsable: $_responsable | Espacio: $_espacio | Estado: $_estado | '
      'Tipo/categoría: $_categoria';

  String _nombreArchivo() {
    final ahora = DateTime.now();
    final marca = '${_codigoFecha(ahora)}_'
        '${ahora.hour.toString().padLeft(2, '0')}'
        '${ahora.minute.toString().padLeft(2, '0')}';
    return 'RegiServ_${_tipoReporte}_$marca';
  }

  Future<void> _exportarExcel() async {
    final filas = _filtradas;
    if (_exportando || _cargando || _incompleto || filas.isEmpty) return;
    setState(() => _exportando = true);
    try {
      final libro = xls.Excel.createExcel();
      final hoja = libro['Sheet1'];
      hoja.appendRow([xls.TextCellValue('REGISERV - $_nombreReporte')]);
      hoja.appendRow([xls.TextCellValue(_resumenFiltros)]);
      hoja.appendRow([xls.TextCellValue('Total registros: ${filas.length}')]);
      hoja.appendRow([xls.TextCellValue('')]);
      hoja.appendRow(_encabezados.map((e) => xls.TextCellValue(e)).toList());
      hoja.setColumnWidth(0, 18);
      hoja.setColumnWidth(1, 23);
      hoja.setColumnWidth(2, 29);
      hoja.setColumnWidth(3, 35);
      hoja.setColumnWidth(4, 23);
      hoja.setColumnWidth(5, 21);
      hoja.setColumnWidth(6, 35);
      hoja.setColumnWidth(7, 23);
      hoja.setColumnWidth(8, 48);
      if (_tipoReporte == 'labores') hoja.setColumnWidth(9, 22);
      for (final fila in filas) {
        hoja.appendRow(_valores(fila).map((v) => xls.TextCellValue(v)).toList());
      }
      final bytes = libro.encode();
      if (bytes == null) throw StateError('Excel no generó contenido.');
      await FileSaver.instance.saveFile(
        name: _nombreArchivo(),
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'xlsx',
        mimeType: MimeType.custom,
        customMimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Se solicitó la descarga del Excel.')),
      );
    } catch (e, stack) {
      debugPrint('ERROR EXPORTAR EXCEL: $e\n$stack');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo generar o descargar el Excel.')),
      );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _exportarPdf() async {
    final filas = _filtradas;
    if (_exportando || _cargando || _incompleto || filas.isEmpty) return;
    if (filas.length > _maximoPdf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'El PDF admite hasta 650 filas. Aplica filtros o descarga Excel.',
        )),
      );
      return;
    }
    setState(() => _exportando = true);
    try {
      final documento = pw.Document();
      final encabezados = _encabezados;
      // Para un PDF legible, el detalle se limita solo en la representación
      // impresa; el Excel conserva el texto completo.
      final datos = filas.map((f) {
        return _valores(f).map((v) =>
            v.length > 110 ? '${v.substring(0, 107)}...' : v).toList();
      }).toList();
      documento.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        maxPages: 250,
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('RegiServ | Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8)),
        ),
        build: (context) => [
          pw.Text('RegiServ | $_nombreReporte',
              style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 7),
          pw.Text(_resumenFiltros, style: const pw.TextStyle(fontSize: 9)),
          pw.Text('Registros: ${filas.length}. Generado: '
              '${_fechaTexto(DateTime.now(), hora: true)}',
              style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: encabezados,
            data: datos,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellPadding: const pw.EdgeInsets.all(4),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Fuente: registros consultados en Supabase. '
              'El detalle de observaciones largas se abrevia en el PDF.',
              style: const pw.TextStyle(fontSize: 8)),
        ],
      ));
      await FileSaver.instance.saveFile(
        name: _nombreArchivo(),
        bytes: await documento.save(),
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Se solicitó la descarga del PDF.')),
      );
    } catch (e, stack) {
      debugPrint('ERROR EXPORTAR PDF: $e\n$stack');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo generar o descargar el PDF.')),
      );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Widget _filtro(String titulo, String valor, List<String> opciones,
      ValueChanged<String?> cambiar) {
    return SizedBox(
      width: 255,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: titulo,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: opciones.contains(valor) ? valor : 'Todos',
            isExpanded: true,
            items: opciones.map((e) => DropdownMenuItem<String>(
              value: e, child: Text(e, overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (_cargando || _exportando) ? null : cambiar,
          ),
        ),
      ),
    );
  }

  Widget _botonFecha(String titulo, DateTime valor, bool inicial) {
    return OutlinedButton.icon(
      onPressed: _cargando ? null : () => _elegirFecha(inicial: inicial),
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text('$titulo: ${_fechaTexto(valor)}'),
    );
  }

  Widget _tablaVistaPrevia(List<_FilaReporte> datos) {
    if (datos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Center(child: Text('No hay registros para los filtros seleccionados.')),
      );
    }
    final muestra = datos.take(30).toList();
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Fecha')),
            DataColumn(label: Text('ID')),
            DataColumn(label: Text('Responsable')),
            DataColumn(label: Text('Espacio')),
            DataColumn(label: Text('Tipo / categoría')),
            DataColumn(label: Text('Estado')),
          ],
          rows: muestra.map((f) => DataRow(cells: [
            DataCell(Text(_fechaTexto(f.fecha))),
            DataCell(Text(f.id)),
            DataCell(Text(f.responsable)),
            DataCell(Text(f.espacio)),
            DataCell(Text(f.categoria)),
            DataCell(Text(f.estado)),
          ])).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_verificando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_autorizado) {
      return Scaffold(
        appBar: AppBar(title: const Text('RegiServ | Reportes')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_errorAcceso ?? 'Acceso denegado.'),
        )),
      );
    }
    final filtradas = _filtradas;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('RegiServ | Reportes de gestión'),
        backgroundColor: Colors.white,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1350),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('Reportes de gestión',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Consultas reales de Supabase. Exclusivo para Supervisor Jefe.',
                  style: TextStyle(color: Color(0xFF64748B))),
              const SizedBox(height: 20),
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('1. Configurar consulta',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 14),
                      Wrap(spacing: 14, runSpacing: 12, children: [
                        SizedBox(
                          width: 300,
                          child: DropdownButtonFormField<String>(
                            initialValue: _tipoReporte,
                            decoration: const InputDecoration(
                              labelText: 'Tipo de reporte',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'labores', child: Text('Labores de aseo')),
                              DropdownMenuItem(value: 'alertas', child: Text('Alertas y observaciones')),
                              DropdownMenuItem(value: 'mantencion', child: Text('Incidencias de Mantención')),
                            ],
                            onChanged: _cargando ? null : (v) {
                              if (v == null) return;
                              setState(() {
                                _tipoReporte = v;
                                _filas = [];
                                _incompleto = false;
                                _error = null;
                                _responsable = 'Todos';
                                _espacio = 'Todos';
                                _estado = 'Todos';
                                _categoria = 'Todos';
                                _fechaConsulta = null;
                              });
                            },
                          ),
                        ),
                        _botonFecha('Desde', _desde, true),
                        _botonFecha('Hasta', _hasta, false),
                        FilledButton.icon(
                          onPressed: _cargando || _exportando ? null : _cargar,
                          icon: const Icon(Icons.search),
                          label: const Text('Consultar'),
                        ),
                      ]),
                      if (_tipoReporte == 'mantencion') ...[
                        const SizedBox(height: 12),
                        const Text('Incluye observaciones derivadas a Mantención; '
                            'no es un reporte de asignación de técnicos ni de tiempos SLA.',
                            style: TextStyle(color: Color(0xFF64748B))),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_cargando) const LinearProgressIndicator(),
              if (_error != null)
                Card(
                  color: const Color(0xFFFFF7ED),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, style: const TextStyle(color: Color(0xFF9A3412))),
                  ),
                ),
              const SizedBox(height: 8),
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('2. Filtrar resultados',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        _filtro('Responsable', _responsable,
                            _opciones((f) => f.responsable),
                            (v) => setState(() => _responsable = v ?? 'Todos')),
                        _filtro('Espacio', _espacio,
                            _opciones((f) => f.espacio),
                            (v) => setState(() => _espacio = v ?? 'Todos')),
                        _filtro('Estado', _estado,
                            _opciones((f) => f.estado),
                            (v) => setState(() => _estado = v ?? 'Todos')),
                        _filtro('Tipo / categoría', _categoria,
                            _opciones((f) => f.categoria),
                            (v) => setState(() => _categoria = v ?? 'Todos')),
                      ]),
                      const SizedBox(height: 18),
                      Row(children: [
                        Expanded(child: Text('Registros: ${filtradas.length}',
                            style: const TextStyle(fontWeight: FontWeight.w600))),
                        if (_fechaConsulta != null)
                          Text('Consulta: ${_fechaTexto(_fechaConsulta, hora: true)}',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                      ]),
                      const SizedBox(height: 12),
                      _tablaVistaPrevia(filtradas),
                      if (filtradas.length > 30)
                        Text('Vista previa: primeras 30 filas de ${filtradas.length}. '
                            'La exportación incluye todas las filas filtradas.',
                            style: const TextStyle(color: Color(0xFF64748B))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('3. Descargar reporte',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      const Text('Se descargarán solamente los resultados que coincidan con los filtros.',
                          style: TextStyle(color: Color(0xFF64748B))),
                      const SizedBox(height: 15),
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        FilledButton.icon(
                          onPressed: filtradas.isEmpty || _cargando ||
                                  _exportando || _incompleto ? null : _exportarExcel,
                          icon: const Icon(Icons.table_view_outlined),
                          label: const Text('Descargar Excel (.xlsx)'),
                        ),
                        OutlinedButton.icon(
                          onPressed: filtradas.isEmpty || _cargando ||
                                  _exportando || _incompleto ? null : _exportarPdf,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Descargar PDF'),
                        ),
                      ]),
                      if (_exportando) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                      ],
                      const SizedBox(height: 10),
                      const Text('Máximo 2.000 registros por consulta. '
                          'Para PDF, máximo 650 filas; usa Excel para mayores volúmenes.',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
