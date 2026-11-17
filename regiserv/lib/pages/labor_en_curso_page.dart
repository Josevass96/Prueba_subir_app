import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/storage/hive_local_storage.dart';
import '../core/labor/labor_operacion_service.dart';
import '../core/remote/supabase_remote_backend.dart';

import '../core/labor/labor_context.dart';

import 'solicitar_cierre_excepcional_page.dart';
import 'auxiliar_home_page.dart';
import 'validar_termino_page.dart';

class LaborEnCursoPage extends StatefulWidget {
  final LaborContext labor;

  const LaborEnCursoPage({super.key, required this.labor});

  @override
  State<LaborEnCursoPage> createState() => _LaborEnCursoPageState();
}

class _LaborEnCursoPageState extends State<LaborEnCursoPage> {
  Timer? temporizador;

  Duration tiempoTranscurrido = Duration.zero;

  DateTime get horaInicio => widget.labor.fechaHoraInicio.toLocal();

  @override
  void initState() {
    super.initState();

    actualizarTiempo();

    temporizador = Timer.periodic(const Duration(seconds: 1), (_) {
      actualizarTiempo();
    });

    // Si la app se abrió tras la aprobación, no devolver al auxiliar
    // a una labor que Supabase ya cerró excepcionalmente.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revisarCierreExcepcionalAlAbrir();
    });
  }

  Future<void> _revisarCierreExcepcionalAlAbrir() async {
    final usuario = Supabase.instance.client.auth.currentUser;
    if (!mounted ||
        usuario == null ||
        usuario.id != widget.labor.idUsuario ||
        widget.labor.idRegistroRemoto == null) {
      return;
    }

    final servicio = LaborOperacionService(
      localStorage: HiveLocalStorage.instance,
      remoteBackend: SupabaseRemoteBackend(Supabase.instance.client),
    );

    final estado = await servicio.reconciliarCierreExcepcional(
      idUsuario: usuario.id,
    );
    if (!mounted) return;

    // La labor aprobada se liberó del Hive del usuario. La solicitud
    // pendiente está técnicamente cerrada en Supabase: aún no es
    // seguro permitir otra labor, pero tampoco mostrarla como activa.
    if (estado == 'aprobada' || estado == 'pendiente') {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (context) => const AuxiliarHomePage()),
        (_) => false,
      );
      return;
    }

    if (estado == 'rechazada') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El cierre excepcional fue rechazado. '
            'Debes continuar la labor anterior.',
          ),
        ),
      );
    }
  }

  void actualizarTiempo() {
    final Duration diferencia = DateTime.now().difference(horaInicio);

    if (!mounted) {
      return;
    }

    setState(() {
      tiempoTranscurrido = diferencia.isNegative ? Duration.zero : diferencia;
    });
  }

  @override
  void dispose() {
    temporizador?.cancel();
    super.dispose();
  }

  String formatearTiempo(Duration duracion) {
    final String horas = duracion.inHours.toString().padLeft(2, '0');

    final String minutos = duracion.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    final String segundos = duracion.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    return '$horas:$minutos:$segundos';
  }

  String formatearHora(DateTime fecha) {
    final String hora = fecha.hour.toString().padLeft(2, '0');

    final String minuto = fecha.minute.toString().padLeft(2, '0');

    return '$hora:$minuto';
  }

  void avanzarTermino() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ValidarTerminoPage(labor: widget.labor),
      ),
    );
  }

  void solicitarCierreExcepcional() {
    if (widget.labor.idRegistroRemoto == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'La solicitud de cierre excepcional necesita sincronizar primero la labor con el servidor.',
            ),
            backgroundColor: Color(0xFFD97706),
          ),
        );

      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SolicitarCierreExcepcionalPage(
          nombreAuxiliar: widget.labor.nombreAuxiliar,
          lugar: widget.labor.lugar,
          horaInicio: horaInicio,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool modoOffline =
        widget.labor.esOffline || widget.labor.requiereSincronizacion == true;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Labor en curso',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: modoOffline
                            ? const Color(0xFFFFFBEB)
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            modoOffline
                                ? Icons.cloud_off_outlined
                                : Icons.timelapse,
                            color: modoOffline
                                ? const Color(0xFFD97706)
                                : const Color(0xFF1565C0),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              modoOffline
                                  ? 'Labor en curso · Modo offline'
                                  : 'Labor en curso',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: modoOffline
                                    ? const Color(0xFF92400E)
                                    : const Color(0xFF1D4ED8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (modoOffline) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'La labor está guardada en este dispositivo y quedará pendiente de sincronización.',
                        style: TextStyle(color: Color(0xFF92400E), height: 1.4),
                      ),
                    ],
                    const SizedBox(height: 24),
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
                            'Lugar',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.labor.lugar,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Auxiliar',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.labor.nombreAuxiliar,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Tiempo transcurrido',
                            style: TextStyle(color: Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            formatearTiempo(tiempoTranscurrido),
                            style: const TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1565C0),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Inicio: ${formatearHora(horaInicio)}',
                            style: const TextStyle(color: Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: avanzarTermino,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text(
                          'Avanzar al término',
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
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: solicitarCierreExcepcional,
                        icon: const Icon(Icons.support_agent_outlined),
                        label: const Text('Solicitar cierre excepcional'),
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
