import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'gestion_edificios_page.dart';
import 'gestion_pisos_page.dart';
import 'gestion_tipos_espacio_page.dart';
import 'gestion_espacios_page.dart';

class GestionSectoresPage extends StatefulWidget {
  const GestionSectoresPage({super.key});

  @override
  State<GestionSectoresPage> createState() => _GestionSectoresPageState();
}

class _GestionSectoresPageState extends State<GestionSectoresPage> {
  SupabaseClient get supabase => Supabase.instance.client;

  bool cargando = true;

  String? mensajeError;

  int cantidadEdificios = 0;
  int cantidadPisos = 0;
  int cantidadTiposEspacio = 0;
  int cantidadEspacios = 0;

  // =============================================================
  // INICIALIZACIÓN
  // =============================================================

  @override
  void initState() {
    super.initState();

    cargarResumen();
  }

  // =============================================================
  // CONTAR REGISTROS ACTIVOS
  // =============================================================

  int contarActivos(List<dynamic> registros) {
    return registros.where((registro) {
      if (registro is Map) {
        return registro['activo'] == true;
      }

      return false;
    }).length;
  }

  // =============================================================
  // CARGAR RESUMEN REAL DESDE SUPABASE
  // =============================================================

  Future<void> cargarResumen() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;
      });
    }

    try {
      // ---------------------------------------------------------
      // EDIFICIOS
      // ---------------------------------------------------------

      final edificios = await supabase
          .from('edificio')
          .select('id_edificio, activo');

      // ---------------------------------------------------------
      // PISOS
      // ---------------------------------------------------------

      final pisos = await supabase.from('piso_nivel').select('id_piso, activo');

      // ---------------------------------------------------------
      // TIPOS DE ESPACIO
      // ---------------------------------------------------------

      final tipos = await supabase
          .from('tipo_espacio')
          .select('id_tipo_espacio, activo');

      // ---------------------------------------------------------
      // ESPACIOS
      // ---------------------------------------------------------

      final espacios = await supabase
          .from('espacio')
          .select('id_espacio, activo');

      if (!mounted) {
        return;
      }

      setState(() {
        cantidadEdificios = contarActivos(edificios);

        cantidadPisos = contarActivos(pisos);

        cantidadTiposEspacio = contarActivos(tipos);

        cantidadEspacios = contarActivos(espacios);

        cargando = false;
      });
    } catch (error) {
      debugPrint('ERROR AL CARGAR SECTORES: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;

        mensajeError =
            'No fue posible cargar el resumen de sectores desde Supabase.';
      });
    }
  }

  // =============================================================
  // ABRIR MÓDULO Y ACTUALIZAR AL VOLVER
  // =============================================================

  Future<void> abrirPagina(Widget pagina) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => pagina),
    );

    if (!mounted) {
      return;
    }

    await cargarResumen();
  }

  // =============================================================
  // CANTIDAD MOSTRADA
  // =============================================================

  String cantidad(int valor) {
    if (cargando) {
      return '...';
    }

    return valor.toString();
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,

        surfaceTintColor: Colors.white,

        title: const Text(
          'Gestión de sectores',

          style: TextStyle(
            fontWeight: FontWeight.bold,

            color: Color(0xFF1F2937),
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Actualizar',

            onPressed: cargando ? null : cargarResumen,

            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: cargarResumen,

          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),

            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),

            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 700),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    // ============================================
                    // CABECERA
                    // ============================================

                    const Text(
                      'Sectores y espacios',

                      style: TextStyle(
                        fontSize: 26,

                        fontWeight: FontWeight.bold,

                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Administra la estructura física utilizada por RegiServ para identificar los lugares donde se realizan las labores de aseo.',

                      style: TextStyle(
                        fontSize: 14,

                        height: 1.4,

                        color: Color(0xFF6B7280),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ============================================
                    // INFORMACIÓN
                    // ============================================
                    Container(
                      width: double.infinity,

                      padding: const EdgeInsets.all(16),

                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),

                        borderRadius: BorderRadius.circular(14),
                      ),

                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Icon(Icons.info_outline, color: Color(0xFF1565C0)),

                          SizedBox(width: 12),

                          Expanded(
                            child: Text(
                              'Los edificios, pisos y espacios que tengan historial no se eliminan. Cuando dejan de utilizarse se marcan como inactivos, conservando la trazabilidad de los registros anteriores.',

                              style: TextStyle(
                                color: Color(0xFF1E40AF),

                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ============================================
                    // ERROR
                    // ============================================
                    if (mensajeError != null) ...[
                      const SizedBox(height: 14),

                      Container(
                        width: double.infinity,

                        padding: const EdgeInsets.all(14),

                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),

                          borderRadius: BorderRadius.circular(12),

                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),

                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,

                              color: Color(0xFFDC2626),
                            ),

                            const SizedBox(width: 10),

                            Expanded(
                              child: Text(
                                mensajeError!,

                                style: const TextStyle(
                                  color: Color(0xFF991B1B),
                                ),
                              ),
                            ),

                            IconButton(
                              tooltip: 'Reintentar',

                              onPressed: cargarResumen,

                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 28),

                    // ============================================
                    // ESTRUCTURA
                    // ============================================
                    const Text(
                      'Estructura del sistema',

                      style: TextStyle(
                        fontSize: 20,

                        fontWeight: FontWeight.bold,

                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Selecciona qué elemento deseas administrar.',

                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),

                    const SizedBox(height: 16),

                    // ============================================
                    // EDIFICIOS
                    // ============================================
                    _TarjetaSector(
                      icono: Icons.apartment_outlined,

                      titulo: 'Edificios',

                      descripcion: 'Crea, edita, activa o desactiva los edificios disponibles.',

                      cantidad: cantidad(cantidadEdificios),

                      detalleCantidad: 'edificios activos',

                      color: const Color(0xFF1565C0),

                      onTap: () {
                        abrirPagina(const GestionEdificiosPage());
                      },
                    ),

                    const SizedBox(height: 12),

                    // ============================================
                    // PISOS
                    // ============================================
                    _TarjetaSector(
                      icono: Icons.layers_outlined,

                      titulo: 'Pisos',

                      descripcion:
                          'Administra los pisos asociados a cada edificio.',

                      cantidad: cantidad(cantidadPisos),

                      detalleCantidad: 'pisos activos',

                      color: const Color(0xFF0F766E),

                      onTap: () {
                        abrirPagina(const GestionPisosPage());
                      },
                    ),

                    const SizedBox(height: 12),

                    // ============================================
                    // TIPOS DE ESPACIO
                    // ============================================
                    _TarjetaSector(
                      icono: Icons.category_outlined,

                      titulo: 'Tipos de espacio',

                      descripcion: 'Administra categorías como Sala, Laboratorio, Baño, Oficina o Pasillo.',

                      cantidad: cantidad(cantidadTiposEspacio),

                      detalleCantidad: 'tipos activos',

                      color: const Color(0xFFD97706),

                      onTap: () {
                        abrirPagina(const GestionTiposEspacioPage());
                      },
                    ),

                    const SizedBox(height: 12),

                    // ============================================
                    // ESPACIOS
                    // ============================================
                    _TarjetaSector(
                      icono: Icons.location_on_outlined,

                      titulo: 'Espacios',

                      descripcion: 'Administra los espacios físicos, código, ubicación GPS y asociación NFC.',

                      cantidad: cantidad(cantidadEspacios),

                      detalleCantidad: 'espacios activos',

                      color: const Color(0xFF7C3AED),

                      onTap: () {
                        abrirPagina(const GestionEspaciosPage());
                      },
                    ),

                    const SizedBox(height: 28),

                    // ============================================
                    // EJEMPLO
                    // ============================================
                    Container(
                      width: double.infinity,

                      padding: const EdgeInsets.all(20),

                      decoration: BoxDecoration(
                        color: Colors.white,

                        borderRadius: BorderRadius.circular(16),

                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),

                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(
                            'Ejemplo de estructura',

                            style: TextStyle(
                              fontSize: 18,

                              fontWeight: FontWeight.bold,

                              color: Color(0xFF1F2937),
                            ),
                          ),

                          SizedBox(height: 16),

                          _FilaEjemplo(titulo: 'Edificio', valor: 'E'),

                          _FilaEjemplo(titulo: 'Piso', valor: '3'),

                          _FilaEjemplo(titulo: 'Tipo', valor: 'Laboratorio'),

                          _FilaEjemplo(titulo: 'Espacio', valor: 'E305'),

                          _FilaEjemplo(
                            titulo: 'Nombre visible',

                            valor: 'Laboratorio E305',

                            mostrarSeparador: false,
                          ),
                        ],
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
}

// =================================================================
// TARJETA DE OPCIÓN
// =================================================================

class _TarjetaSector extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String descripcion;
  final String cantidad;
  final String detalleCantidad;
  final Color color;
  final VoidCallback onTap;

  const _TarjetaSector({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.cantidad,
    required this.detalleCantidad,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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

          child: Row(
            children: [
              Container(
                width: 52,

                height: 52,

                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),

                  borderRadius: BorderRadius.circular(13),
                ),

                child: Icon(icono, color: color, size: 27),
              ),

              const SizedBox(width: 15),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      titulo,

                      style: const TextStyle(
                        fontSize: 17,

                        fontWeight: FontWeight.bold,

                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      descripcion,

                      style: const TextStyle(
                        fontSize: 13,

                        height: 1.3,

                        color: Color(0xFF6B7280),
                      ),
                    ),

                    const SizedBox(height: 9),

                    Row(
                      children: [
                        Text(
                          cantidad,

                          style: TextStyle(
                            fontSize: 15,

                            fontWeight: FontWeight.bold,

                            color: color,
                          ),
                        ),

                        const SizedBox(width: 5),

                        Text(
                          detalleCantidad,

                          style: const TextStyle(
                            fontSize: 12,

                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }
}

// =================================================================
// FILA DE EJEMPLO
// =================================================================

class _FilaEjemplo extends StatelessWidget {
  final String titulo;
  final String valor;
  final bool mostrarSeparador;

  const _FilaEjemplo({
    required this.titulo,
    required this.valor,
    this.mostrarSeparador = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 120,

              child: Text(
                titulo,

                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ),

            Expanded(
              child: Text(
                valor,

                style: const TextStyle(
                  fontSize: 15,

                  fontWeight: FontWeight.w600,

                  color: Color(0xFF1F2937),
                ),
              ),
            ),
          ],
        ),

        if (mostrarSeparador) ...[
          const SizedBox(height: 12),

          const Divider(),

          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
