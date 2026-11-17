import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'nuevo_usuario_page.dart';
import 'editar_usuario_page.dart';

class GestionUsuariosPage extends StatefulWidget {
  const GestionUsuariosPage({super.key});

  @override
  State<GestionUsuariosPage> createState() => _GestionUsuariosPageState();
}

class _GestionUsuariosPageState extends State<GestionUsuariosPage> {
  final TextEditingController buscarController = TextEditingController();

  SupabaseClient get supabase => Supabase.instance.client;

  List<Map<String, dynamic>> usuarios = [];

  Map<String, int> idsEstadoPorNombre = {};

  String filtroEstado = 'Todos';

  String textoBusqueda = '';

  bool cargando = true;

  String? mensajeError;

  String? usuarioProcesando;

  // =============================================================
  // INICIALIZACIÓN
  // =============================================================

  @override
  void initState() {
    super.initState();

    cargarUsuarios();
  }

  @override
  void dispose() {
    buscarController.dispose();

    super.dispose();
  }

  // =============================================================
  // FORMATEAR RUT
  // =============================================================

  String formatearRut(dynamic rut, dynamic dv) {
    String numero = (rut ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');

    final digito = (dv ?? '').toString().toUpperCase();

    if (numero.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();

    int contador = 0;

    for (int i = numero.length - 1; i >= 0; i--) {
      if (contador == 3) {
        buffer.write('.');

        contador = 0;
      }

      buffer.write(numero[i]);

      contador++;
    }

    final invertido = buffer.toString().split('').reversed.join();

    return '$invertido-$digito';
  }

  // =============================================================
  // NOMBRE COMPLETO
  // =============================================================

  String construirNombre(Map<String, dynamic> usuario) {
    final partes =
        [
              usuario['p_nombre'],
              usuario['s_nombre'],
              usuario['apellido_pater'],
              usuario['apellido_mater'],
            ]
            .map((valor) => (valor ?? '').toString().trim())
            .where((valor) => valor.isNotEmpty)
            .toList();

    return partes.join(' ');
  }

  // =============================================================
  // CARGAR USUARIOS
  // =============================================================

  Future<void> cargarUsuarios() async {
    if (mounted) {
      setState(() {
        cargando = true;
        mensajeError = null;
      });
    }

    try {
      // ---------------------------------------------------------
      // ROLES
      // ---------------------------------------------------------

      final rolesData = await supabase.from('rol').select('id_rol, nombre');

      final Map<int, String> rolesTemporales = {};

      for (final rol in rolesData) {
        final id = int.tryParse(rol['id_rol'].toString());

        if (id != null) {
          rolesTemporales[id] = (rol['nombre'] ?? '').toString();
        }
      }

      // ---------------------------------------------------------
      // ESTADOS
      // ---------------------------------------------------------

      final estadosData = await supabase
          .from('estado_usuario')
          .select('id_estado_usuario, nombre_estado');

      final Map<String, int> estadosTemporales = {};

      for (final estado in estadosData) {
        final id = int.tryParse(estado['id_estado_usuario'].toString());

        final nombre = (estado['nombre_estado'] ?? '').toString();

        if (id != null && nombre.isNotEmpty) {
          estadosTemporales[nombre] = id;
        }
      }

      // ---------------------------------------------------------
      // USUARIOS
      // ---------------------------------------------------------

      final usuariosData = await supabase
          .from('usuario')
          .select(
            'id_usuario, '
            'id_rol, '
            'id_estado_usuario, '
            'id_sede, '
            'p_nombre, '
            's_nombre, '
            'apellido_pater, '
            'apellido_mater, '
            'rut, '
            'dv, '
            'email, '
            'activo, '
            'primer_acceso',
          );

      final List<Map<String, dynamic>> usuariosTemporales = [];

      for (final fila in usuariosData) {
        final usuario = Map<String, dynamic>.from(fila);

        final idRol = int.tryParse(usuario['id_rol'].toString());

        usuariosTemporales.add({
          ...usuario,

          'id': usuario['id_usuario'],

          'nombre': construirNombre(usuario),

          'rut_formateado': formatearRut(usuario['rut'], usuario['dv']),

          'correo': usuario['email'],

          'rol': rolesTemporales[idRol] ?? 'Sin rol',
        });
      }

      usuariosTemporales.sort(
        (a, b) => a['nombre'].toString().toLowerCase().compareTo(
          b['nombre'].toString().toLowerCase(),
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        idsEstadoPorNombre = estadosTemporales;

        usuarios = usuariosTemporales;

        cargando = false;
      });
    } catch (error) {
      debugPrint('ERROR AL CARGAR USUARIOS: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        cargando = false;

        mensajeError = 'No fue posible cargar los usuarios desde Supabase.';
      });
    }
  }

  // =============================================================
  // FILTROS
  // =============================================================

  List<Map<String, dynamic>> get usuariosFiltrados {
    return usuarios.where((usuario) {
      final activo = usuario['activo'] == true;

      final cumpleEstado =
          filtroEstado == 'Todos' ||
          (filtroEstado == 'Activos' && activo) ||
          (filtroEstado == 'Inactivos' && !activo);

      final busqueda = textoBusqueda.trim().toLowerCase();

      final nombre = (usuario['nombre'] ?? '').toString().toLowerCase();

      final rut = (usuario['rut_formateado'] ?? '').toString().toLowerCase();

      final correo = (usuario['correo'] ?? '').toString().toLowerCase();

      final rol = (usuario['rol'] ?? '').toString().toLowerCase();

      final cumpleBusqueda =
          busqueda.isEmpty ||
          nombre.contains(busqueda) ||
          rut.contains(busqueda) ||
          correo.contains(busqueda) ||
          rol.contains(busqueda);

      return cumpleEstado && cumpleBusqueda;
    }).toList();
  }

  // =============================================================
  // NUEVO USUARIO
  // =============================================================

  Future<void> nuevoUsuario() async {
    final creado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const NuevoUsuarioPage()),
    );

    if (creado != true || !mounted) {
      return;
    }

    await cargarUsuarios();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Usuario creado correctamente.'),

        backgroundColor: Color(0xFF16A34A),
      ),
    );
  }

  // =============================================================
  // EDITAR USUARIO REAL
  // =============================================================

  Future<void> editarUsuario(Map<String, dynamic> usuario) async {
    final actualizado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditarUsuarioPage(usuario: usuario),
      ),
    );

    if (actualizado != true || !mounted) {
      return;
    }

    // Vuelve a consultar PostgreSQL.
    await cargarUsuarios();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Usuario actualizado correctamente.'),

        backgroundColor: Color(0xFF16A34A),
      ),
    );
  }

  // =============================================================
  // CAMBIAR ESTADO
  // =============================================================

  Future<void> cambiarEstado(Map<String, dynamic> usuario) async {
    final idUsuario = usuario['id_usuario'].toString();

    final idUsuarioActual = supabase.auth.currentUser?.id;

    // -----------------------------------------------------------
    // NO DESACTIVARSE A SÍ MISMO
    // -----------------------------------------------------------

    if (idUsuarioActual == idUsuario && usuario['activo'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No puedes desactivar tu propia cuenta mientras tienes una sesión activa.',
          ),
        ),
      );

      return;
    }

    final activo = usuario['activo'] == true;

    final nuevoEstado = !activo;

    final nombreUsuario = usuario['nombre'].toString();

    final confirmar = await showDialog<bool>(
      context: context,

      builder: (context) {
        return AlertDialog(
          title: Text(activo ? 'Desactivar usuario' : 'Activar usuario'),

          content: Text(
            activo
                ? '¿Deseas desactivar a $nombreUsuario? '
                      'El usuario conservará todo su historial, '
                      'pero no podrá acceder a RegiServ.'
                : '¿Deseas activar nuevamente a $nombreUsuario?',
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },

              child: const Text('Cancelar'),
            ),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },

              style: ElevatedButton.styleFrom(
                backgroundColor: activo
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF16A34A),

                foregroundColor: Colors.white,
              ),

              child: Text(activo ? 'Desactivar' : 'Activar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      return;
    }

    final nombreEstado = nuevoEstado ? 'Activo' : 'Inactivo';

    final idEstado = idsEstadoPorNombre[nombreEstado];

    if (idEstado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se encontró el estado "$nombreEstado" en la base de datos.',
          ),
        ),
      );

      return;
    }

    setState(() {
      usuarioProcesando = idUsuario;
    });

    try {
      await supabase
          .from('usuario')
          .update({'activo': nuevoEstado, 'id_estado_usuario': idEstado})
          .eq('id_usuario', idUsuario);

      await cargarUsuarios();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nuevoEstado
                ? 'Usuario activado correctamente.'
                : 'Usuario desactivado correctamente.',
          ),
        ),
      );
    } catch (error) {
      debugPrint('ERROR AL CAMBIAR ESTADO: $error');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible actualizar el estado del usuario.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          usuarioProcesando = null;
        });
      }
    }
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final lista = usuariosFiltrados;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,

        surfaceTintColor: Colors.white,

        title: const Text(
          'Gestión de usuarios',

          style: TextStyle(
            fontWeight: FontWeight.bold,

            color: Color(0xFF1F2937),
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Actualizar',

            onPressed: cargando ? null : cargarUsuarios,

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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [
                                Text(
                                  'Usuarios del sistema',

                                  style: TextStyle(
                                    fontSize: 24,

                                    fontWeight: FontWeight.bold,

                                    color: Color(0xFF1F2937),
                                  ),
                                ),

                                SizedBox(height: 5),

                                Text(
                                  'Administra las cuentas y roles de acceso a RegiServ.',

                                  style: TextStyle(
                                    color: Color(0xFF6B7280),

                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 12),

                          ElevatedButton.icon(
                            onPressed: nuevoUsuario,

                            icon: const Icon(Icons.person_add_alt_1_outlined),

                            label: const Text('Nuevo'),

                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),

                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      TextField(
                        controller: buscarController,

                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre, RUT, correo o rol...',

                          prefixIcon: const Icon(Icons.search),

                          suffixIcon: textoBusqueda.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    buscarController.clear();

                                    setState(() {
                                      textoBusqueda = '';
                                    });
                                  },

                                  icon: const Icon(Icons.close),
                                )
                              : null,

                          filled: true,

                          fillColor: Colors.white,

                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),

                        onChanged: (valor) {
                          setState(() {
                            textoBusqueda = valor;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,

                        child: Row(
                          children: [
                            _FiltroUsuario(
                              texto: 'Todos',

                              seleccionado: filtroEstado == 'Todos',

                              onTap: () {
                                setState(() {
                                  filtroEstado = 'Todos';
                                });
                              },
                            ),

                            const SizedBox(width: 8),

                            _FiltroUsuario(
                              texto: 'Activos',

                              seleccionado: filtroEstado == 'Activos',

                              onTap: () {
                                setState(() {
                                  filtroEstado = 'Activos';
                                });
                              },
                            ),

                            const SizedBox(width: 8),

                            _FiltroUsuario(
                              texto: 'Inactivos',

                              seleccionado: filtroEstado == 'Inactivos',

                              onTap: () {
                                setState(() {
                                  filtroEstado = 'Inactivos';
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      if (!cargando)
                        Text(
                          '${lista.length} ${lista.length == 1 ? 'usuario encontrado' : 'usuarios encontrados'}',

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
                      ? _ErrorUsuarios(
                          mensaje: mensajeError!,

                          onReintentar: cargarUsuarios,
                        )
                      : lista.isEmpty
                      ? const _SinUsuarios()
                      : RefreshIndicator(
                          onRefresh: cargarUsuarios,

                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),

                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),

                            itemCount: lista.length,

                            itemBuilder: (context, index) {
                              final usuario = lista[index];

                              final procesando =
                                  usuarioProcesando ==
                                  usuario['id_usuario'].toString();

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),

                                child: _TarjetaUsuario(
                                  usuario: usuario,

                                  procesando: procesando,

                                  onCambiarEstado: () {
                                    cambiarEstado(usuario);
                                  },

                                  onEditar: () {
                                    editarUsuario(usuario);
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

class _FiltroUsuario extends StatelessWidget {
  final String texto;
  final bool seleccionado;
  final VoidCallback onTap;

  const _FiltroUsuario({
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
// TARJETA
// =================================================================

class _TarjetaUsuario extends StatelessWidget {
  final Map<String, dynamic> usuario;

  final VoidCallback onEditar;

  final VoidCallback onCambiarEstado;

  final bool procesando;

  const _TarjetaUsuario({
    required this.usuario,
    required this.onEditar,
    required this.onCambiarEstado,
    required this.procesando,
  });

  @override
  Widget build(BuildContext context) {
    final activo = usuario['activo'] == true;

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Container(
                width: 48,

                height: 48,

                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),

                  borderRadius: BorderRadius.circular(12),
                ),

                child: const Icon(
                  Icons.person_outline,

                  color: Color(0xFF1565C0),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      usuario['nombre'].toString(),

                      style: const TextStyle(
                        fontSize: 17,

                        fontWeight: FontWeight.bold,

                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      usuario['rol'].toString(),

                      style: const TextStyle(
                        fontSize: 13,

                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),

              if (procesando)
                const Padding(
                  padding: EdgeInsets.all(10),

                  child: SizedBox(
                    width: 20,

                    height: 20,

                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),

                  onSelected: (valor) {
                    if (valor == 'editar') {
                      onEditar();
                    }

                    if (valor == 'estado') {
                      onCambiarEstado();
                    }
                  },

                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'editar',

                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined),

                          SizedBox(width: 10),

                          Text('Editar'),
                        ],
                      ),
                    ),

                    PopupMenuItem(
                      value: 'estado',

                      child: Row(
                        children: [
                          Icon(
                            activo
                                ? Icons.person_off_outlined
                                : Icons.person_add_alt_outlined,

                            color: activo
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF16A34A),
                          ),

                          const SizedBox(width: 10),

                          Text(activo ? 'Desactivar' : 'Activar'),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),

          const SizedBox(height: 16),

          const Divider(),

          const SizedBox(height: 12),

          _DatoUsuario(
            icono: Icons.badge_outlined,

            texto: usuario['rut_formateado'].toString(),
          ),

          const SizedBox(height: 10),

          _DatoUsuario(
            icono: Icons.email_outlined,

            texto: usuario['correo'].toString(),
          ),

          const SizedBox(height: 14),

          Align(
            alignment: Alignment.centerLeft,

            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),

              decoration: BoxDecoration(
                color: activo
                    ? const Color(0xFFF0FDF4)
                    : const Color(0xFFF3F4F6),

                borderRadius: BorderRadius.circular(20),
              ),

              child: Text(
                activo ? 'Activo' : 'Inactivo',

                style: TextStyle(
                  fontSize: 12,

                  fontWeight: FontWeight.w600,

                  color: activo
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF6B7280),
                ),
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

class _DatoUsuario extends StatelessWidget {
  final IconData icono;

  final String texto;

  const _DatoUsuario({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, size: 18, color: const Color(0xFF6B7280)),

        const SizedBox(width: 8),

        Expanded(
          child: Text(
            texto,

            style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
          ),
        ),
      ],
    );
  }
}

// =================================================================
// ERROR
// =================================================================

class _ErrorUsuarios extends StatelessWidget {
  final String mensaje;

  final Future<void> Function() onReintentar;

  const _ErrorUsuarios({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            const Icon(
              Icons.cloud_off_outlined,

              size: 58,

              color: Color(0xFF9CA3AF),
            ),

            const SizedBox(height: 14),

            Text(
              mensaje,

              textAlign: TextAlign.center,

              style: const TextStyle(fontSize: 16, color: Color(0xFF4B5563)),
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
// SIN USUARIOS
// =================================================================

class _SinUsuarios extends StatelessWidget {
  const _SinUsuarios();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Icon(Icons.people_outline, size: 58, color: Color(0xFF9CA3AF)),

            SizedBox(height: 14),

            Text(
              'No se encontraron usuarios',

              style: TextStyle(
                fontSize: 18,

                fontWeight: FontWeight.bold,

                color: Color(0xFF1F2937),
              ),
            ),

            SizedBox(height: 6),

            Text(
              'Modifica la búsqueda o los filtros para encontrar usuarios.',

              textAlign: TextAlign.center,

              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
