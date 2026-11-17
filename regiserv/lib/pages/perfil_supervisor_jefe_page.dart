import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PerfilSupervisorJefePage extends StatefulWidget {
  const PerfilSupervisorJefePage({super.key});

  @override
  State<PerfilSupervisorJefePage> createState() =>
      _PerfilSupervisorJefePageState();
}

class _PerfilSupervisorJefePageState extends State<PerfilSupervisorJefePage> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool cargando = true;
  String? mensajeError;

  Map<String, dynamic>? usuario;

  @override
  void initState() {
    super.initState();
    cargarPerfil();
  }

  Future<void> cargarPerfil() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;
      });
    }

    try {
      final authUser = supabase.auth.currentUser;

      if (authUser == null) {
        throw Exception('No existe una sesión autenticada.');
      }

      final Map<String, dynamic> datos = await supabase
          .from('usuario')
          .select(
            'id_usuario, '
            'p_nombre, '
            's_nombre, '
            'apellido_pater, '
            'apellido_mater, '
            'rut, '
            'dv, '
            'email, '
            'activo',
          )
          .eq('id_usuario', authUser.id)
          .single();

      if (!mounted) {
        return;
      }

      setState(() {
        usuario = datos;
        cargando = false;
      });
    } catch (error, stackTrace) {
      debugPrint('ERROR cargarPerfil Supervisor Jefe: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;
        mensajeError = 'No fue posible cargar la información del perfil.';
      });
    }
  }

  String get nombreCompleto {
    final datos = usuario;

    if (datos == null) {
      return '—';
    }

    return [
          datos['p_nombre'],
          datos['s_nombre'],
          datos['apellido_pater'],
          datos['apellido_mater'],
        ]
        .map((valor) => (valor ?? '').toString().trim())
        .where((valor) => valor.isNotEmpty)
        .join(' ');
  }

  String get inicial {
    final String nombre = (usuario?['p_nombre'] ?? '').toString().trim();

    if (nombre.isEmpty) {
      return 'S';
    }

    return nombre.substring(0, 1).toUpperCase();
  }

  String get rutFormateado {
    final String cuerpo = (usuario?['rut'] ?? '').toString().trim();

    final String dv = (usuario?['dv'] ?? '').toString().trim().toUpperCase();

    if (cuerpo.isEmpty) {
      return '—';
    }

    final String reverso = cuerpo.split('').reversed.join();

    final List<String> grupos = [];

    for (int i = 0; i < reverso.length; i += 3) {
      final int fin = (i + 3 < reverso.length) ? i + 3 : reverso.length;

      grupos.add(reverso.substring(i, fin));
    }

    final String conPuntos = grupos
        .map((grupo) => grupo.split('').reversed.join())
        .toList()
        .reversed
        .join('.');

    return dv.isEmpty ? conPuntos : '$conPuntos-$dv';
  }

  Widget itemPerfil({
    required IconData icono,
    required String titulo,
    required String valor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,

        children: [
          Container(
            width: 50,
            height: 50,

            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),

            child: Icon(icono, color: const Color(0xFF1565C0)),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                ),

                const SizedBox(height: 3),

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
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Mi perfil',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
      ),

      body: SafeArea(
        child: cargando
            ? const Center(child: CircularProgressIndicator())
            : mensajeError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 52,
                        color: Color(0xFFDC2626),
                      ),

                      const SizedBox(height: 12),

                      Text(mensajeError!, textAlign: TextAlign.center),

                      const SizedBox(height: 16),

                      ElevatedButton.icon(
                        onPressed: cargarPerfil,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),

                child: Center(
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 650),

                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(28),

                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),

                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 46,
                                backgroundColor: const Color(0xFF1565C0),
                                child: Text(
                                  inicial,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 34,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 18),

                              Text(
                                nombreCompleto,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1F2937),
                                ),
                              ),

                              const SizedBox(height: 6),

                              const Text(
                                'Administrador del sistema',
                                style: TextStyle(color: Color(0xFF6B7280)),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),

                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),

                          child: Column(
                            children: [
                              itemPerfil(
                                icono: Icons.badge_outlined,
                                titulo: 'RUT',
                                valor: rutFormateado,
                              ),

                              const Divider(),

                              itemPerfil(
                                icono: Icons.email_outlined,
                                titulo: 'Correo',
                                valor: (usuario?['email'] ?? '—').toString(),
                              ),

                              const Divider(),

                              itemPerfil(
                                icono: Icons.manage_accounts_outlined,
                                titulo: 'Rol',
                                valor: 'Supervisor Jefe',
                              ),

                              const Divider(),

                              itemPerfil(
                                icono: Icons.check_circle_outline,
                                titulo: 'Estado',
                                valor: usuario?['activo'] == true
                                    ? 'Activo'
                                    : 'Inactivo',
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
