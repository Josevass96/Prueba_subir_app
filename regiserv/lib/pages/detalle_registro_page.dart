import 'package:flutter/material.dart';

class DetalleRegistroPage extends StatelessWidget {
  final String fecha;
  final String nombreAuxiliar;
  final String lugar;
  final String inicio;
  final String termino;
  final String duracion;
  final String estado;

  // Estos datos son opcionales porque dependen
  // del estado seleccionado al finalizar la labor.
  final String? motivoParcial;
  final String? categoriaObservacion;
  final String? detalleObservacion;

  const DetalleRegistroPage({
    super.key,
    required this.fecha,
    required this.nombreAuxiliar,
    required this.lugar,
    required this.inicio,
    required this.termino,
    required this.duracion,
    required this.estado,
    this.motivoParcial,
    this.categoriaObservacion,
    this.detalleObservacion,
  });

  // Color utilizado según el estado del aseo.
  Color obtenerColorEstado() {
    switch (estado) {
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
    switch (estado) {
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

  @override
  Widget build(BuildContext context) {
    final colorEstado = obtenerColorEstado();
    final fondoEstado = obtenerFondoEstado();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,

        title: const Text(
          'Detalle del registro',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),

          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ------------------------------------------------
                  // ESTADO
                  // ------------------------------------------------

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),

                    decoration: BoxDecoration(
                      color: fondoEstado,
                      borderRadius: BorderRadius.circular(20),
                    ),

                    child: Text(
                      estado,
                      style: TextStyle(
                        color: colorEstado,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ------------------------------------------------
                  // DATOS GENERALES
                  // ------------------------------------------------
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),

                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Información de la labor',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),

                        const SizedBox(height: 20),

                        _DatoDetalle(titulo: 'Auxiliar', valor: nombreAuxiliar),

                        _DatoDetalle(titulo: 'Lugar', valor: lugar),

                        _DatoDetalle(titulo: 'Fecha', valor: fecha),

                        const Divider(height: 30),

                        Row(
                          children: [
                            Expanded(
                              child: _DatoDetalle(
                                titulo: 'Inicio',
                                valor: inicio,
                              ),
                            ),

                            Expanded(
                              child: _DatoDetalle(
                                titulo: 'Término',
                                valor: termino,
                              ),
                            ),
                          ],
                        ),

                        _DatoDetalle(titulo: 'Duración', valor: duracion),
                      ],
                    ),
                  ),

                  // ------------------------------------------------
                  // SI FUE PARCIAL
                  // ------------------------------------------------
                  if (estado == 'Parcial' && motivoParcial != null) ...[
                    const SizedBox(height: 18),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),

                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(16),
                      ),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Motivo',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF92400E),
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            motivoParcial!,
                            style: const TextStyle(color: Color(0xFF78350F)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ------------------------------------------------
                  // SI FUE CON OBSERVACIONES
                  // ------------------------------------------------
                  if (estado == 'Con Observaciones') ...[
                    const SizedBox(height: 18),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),

                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(16),
                      ),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Observación',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF991B1B),
                            ),
                          ),

                          const SizedBox(height: 14),

                          _DatoDetalle(
                            titulo: 'Categoría',
                            valor: categoriaObservacion ?? 'Sin categoría',
                          ),

                          _DatoDetalle(
                            titulo: 'Detalle',
                            valor: detalleObservacion ?? 'Sin detalle',
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // ------------------------------------------------
                  // FOTOGRAFÍA
                  // ------------------------------------------------
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),

                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Fotografía',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Por ahora usamos un marcador visual.
                        // Más adelante aquí mostraremos la foto real.
                        Container(
                          width: double.infinity,
                          height: 180,

                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                          ),

                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.photo_outlined,
                                size: 48,
                                color: Color(0xFF1565C0),
                              ),

                              SizedBox(height: 10),

                              Text(
                                'Evidencia fotográfica',
                                style: TextStyle(color: Color(0xFF6B7280)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ------------------------------------------------
                  // SINCRONIZACIÓN
                  // ------------------------------------------------
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),

                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(14),
                    ),

                    child: const Row(
                      children: [
                        Icon(
                          Icons.cloud_done_outlined,
                          color: Color(0xFF16A34A),
                        ),

                        SizedBox(width: 10),

                        Text(
                          'Registro sincronizado',
                          style: TextStyle(
                            color: Color(0xFF166534),
                            fontWeight: FontWeight.w600,
                          ),
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
    );
  }
}

// Widget reutilizable para mostrar un dato y su valor.
class _DatoDetalle extends StatelessWidget {
  final String titulo;
  final String valor;

  const _DatoDetalle({required this.titulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),

          const SizedBox(height: 4),

          Text(
            valor,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }
}
