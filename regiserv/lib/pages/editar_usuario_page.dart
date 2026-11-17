import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/sesion_data.dart';
import '../utils/rut_formatter.dart';

class EditarUsuarioPage extends StatefulWidget {
  final Map<String, dynamic> usuario;

  const EditarUsuarioPage({super.key, required this.usuario});

  @override
  State<EditarUsuarioPage> createState() => _EditarUsuarioPageState();
}

class _EditarUsuarioPageState extends State<EditarUsuarioPage> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  late TextEditingController primerNombreController;
  late TextEditingController segundoNombreController;
  late TextEditingController apellidoPaternoController;
  late TextEditingController apellidoMaternoController;
  late TextEditingController rutController;
  late TextEditingController correoController;

  late String rolSeleccionado;

  bool guardando = false;

  final List<String> roles = [
    'Auxiliar',
    'Supervisor',
    'Supervisor Jefe',
    'Mantención',
  ];

  SupabaseClient get supabase => Supabase.instance.client;

  // =============================================================
  // INICIALIZACIÓN
  // =============================================================

  @override
  void initState() {
    super.initState();

    primerNombreController = TextEditingController(
      text: (widget.usuario['p_nombre'] ?? '').toString(),
    );

    segundoNombreController = TextEditingController(
      text: (widget.usuario['s_nombre'] ?? '').toString(),
    );

    apellidoPaternoController = TextEditingController(
      text: (widget.usuario['apellido_pater'] ?? '').toString(),
    );

    apellidoMaternoController = TextEditingController(
      text: (widget.usuario['apellido_mater'] ?? '').toString(),
    );

    final rutFormateado = (widget.usuario['rut_formateado'] ?? '').toString();

    if (rutFormateado.isNotEmpty) {
      rutController = TextEditingController(text: rutFormateado);
    } else {
      final rut = (widget.usuario['rut'] ?? '').toString();

      final dv = (widget.usuario['dv'] ?? '').toString();

      rutController = TextEditingController(text: '$rut-$dv');
    }

    correoController = TextEditingController(
      text: (widget.usuario['email'] ?? widget.usuario['correo'] ?? '')
          .toString(),
    );

    rolSeleccionado = (widget.usuario['rol'] ?? 'Auxiliar').toString();
  }

  @override
  void dispose() {
    primerNombreController.dispose();
    segundoNombreController.dispose();
    apellidoPaternoController.dispose();
    apellidoMaternoController.dispose();
    rutController.dispose();
    correoController.dispose();

    super.dispose();
  }

  // =============================================================
  // VALIDAR CORREO
  // =============================================================

  bool correoValido(String correo) {
    final expresion = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    return expresion.hasMatch(correo);
  }

  // =============================================================
  // MENSAJE DEVUELTO POR EDGE FUNCTION
  // =============================================================

  String obtenerMensajeError(FunctionException error) {
    final details = error.details;

    if (details is Map) {
      final mensaje = details['error'];

      if (mensaje != null) {
        return mensaje.toString();
      }
    }

    if (details != null) {
      final texto = details.toString();

      if (texto.isNotEmpty) {
        return texto;
      }
    }

    return 'No fue posible actualizar el usuario.';
  }

  // =============================================================
  // GUARDAR CAMBIOS
  // =============================================================

  Future<void> guardarCambios() async {
    if (guardando) {
      return;
    }

    if (!formKey.currentState!.validate()) {
      return;
    }

    // -----------------------------------------------------------
    // VALIDAR SESIÓN
    // -----------------------------------------------------------

    final session = supabase.auth.currentSession;

    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La sesión ha expirado. Inicia sesión nuevamente.'),
        ),
      );

      return;
    }

    // -----------------------------------------------------------
    // CONFIRMAR
    // -----------------------------------------------------------

    final confirmar = await showDialog<bool>(
      context: context,

      builder: (context) {
        return AlertDialog(
          title: const Text('Guardar cambios'),

          content: const Text(
            '¿Deseas guardar las modificaciones realizadas a este usuario?',
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
                backgroundColor: const Color(0xFF1565C0),

                foregroundColor: Colors.white,
              ),

              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      return;
    }

    // -----------------------------------------------------------
    // PREPARAR RUT
    // -----------------------------------------------------------

    final rutCompleto = rutController.text
        .replaceAll(RegExp(r'[^0-9kK]'), '')
        .toUpperCase();

    if (rutCompleto.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El RUT ingresado no es válido.')),
      );

      return;
    }

    final rut = rutCompleto.substring(0, rutCompleto.length - 1);

    final dv = rutCompleto.substring(rutCompleto.length - 1);

    final idUsuario = widget.usuario['id_usuario'].toString();

    // -----------------------------------------------------------
    // INICIAR PROCESO
    // -----------------------------------------------------------

    setState(() {
      guardando = true;
    });

    try {
      // =========================================================
      // EDGE FUNCTION
      // =========================================================

      final respuesta = await supabase.functions.invoke(
        'actualizar-usuario',

        headers: {'Authorization': 'Bearer ${session.accessToken}'},

        body: {
          'idUsuario': idUsuario,

          'pNombre': primerNombreController.text.trim(),

          'sNombre': segundoNombreController.text.trim().isEmpty
              ? null
              : segundoNombreController.text.trim(),

          'apellidoPater': apellidoPaternoController.text.trim(),

          'apellidoMater': apellidoMaternoController.text.trim().isEmpty
              ? null
              : apellidoMaternoController.text.trim(),

          'rut': rut,

          'dv': dv,

          'email': correoController.text.trim().toLowerCase(),

          'rol': rolSeleccionado,
        },
      );

      final data = respuesta.data;

      debugPrint('RESPUESTA ACTUALIZAR USUARIO: $data');

      if (data is! Map || data['ok'] != true) {
        throw Exception('La función no confirmó la actualización.');
      }

      // =========================================================
      // SI EL SUPERVISOR JEFE SE EDITÓ A SÍ MISMO
      // =========================================================

      final usuarioActualId = supabase.auth.currentUser?.id;

      if (usuarioActualId == idUsuario) {
        // Actualiza los datos de Auth,
        // por ejemplo si cambió el correo.
        try {
          await supabase.auth.refreshSession();
        } catch (error) {
          debugPrint('No fue posible refrescar Auth: $error');
        }

        // Actualiza también SesionData,
        // para que el nombre mostrado cambie
        // inmediatamente.
        SesionData.iniciarSesionDesdeSupabase(
          perfil: {
            'id_usuario': idUsuario,

            'id_rol': widget.usuario['id_rol'],

            'id_estado_usuario': widget.usuario['id_estado_usuario'],

            'id_sede': widget.usuario['id_sede'],

            'p_nombre': primerNombreController.text.trim(),

            's_nombre': segundoNombreController.text.trim().isEmpty
                ? null
                : segundoNombreController.text.trim(),

            'apellido_pater': apellidoPaternoController.text.trim(),

            'apellido_mater': apellidoMaternoController.text.trim().isEmpty
                ? null
                : apellidoMaternoController.text.trim(),

            'rut': rut,

            'dv': dv,

            'email': correoController.text.trim().toLowerCase(),

            'activo': widget.usuario['activo'],

            'primer_acceso': widget.usuario['primer_acceso'],
          },

          rol: rolSeleccionado,
        );
      }

      if (!mounted) {
        return;
      }

      // ---------------------------------------------------------
      // INDICAR ÉXITO A GESTIÓN DE USUARIOS
      // ---------------------------------------------------------

      Navigator.pop(context, true);
    }
    // ===========================================================
    // ERROR EDGE FUNCTION
    // ===========================================================
    on FunctionException catch (error) {
      debugPrint(
        'ERROR EDGE FUNCTION ACTUALIZAR: '
        '${error.status} '
        '${error.details}',
      );

      if (!mounted) {
        return;
      }

      final mensaje = obtenerMensajeError(error);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensaje),

          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
    // ===========================================================
    // OTROS ERRORES
    // ===========================================================
    catch (error) {
      debugPrint('ERROR ACTUALIZAR USUARIO: $error');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No fue posible actualizar el usuario. Revisa la conexión con Supabase.',
          ),

          backgroundColor: Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          guardando = false;
        });
      }
    }
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
          'Editar usuario',

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
              constraints: const BoxConstraints(maxWidth: 650),

              child: Form(
                key: formKey,

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
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
                              'Puedes modificar los datos personales, correo y rol. La contraseña y el estado de la cuenta se administran por separado.',

                              style: TextStyle(
                                color: Color(0xFF1E40AF),

                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'Datos personales',

                      style: TextStyle(
                        fontSize: 21,

                        fontWeight: FontWeight.bold,

                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ============================================
                    // PRIMER NOMBRE
                    // ============================================
                    TextFormField(
                      controller: primerNombreController,

                      enabled: !guardando,

                      textCapitalization: TextCapitalization.words,

                      decoration: _decoracionCampo(
                        etiqueta: 'Primer nombre *',

                        icono: Icons.person_outline,
                      ),

                      validator: (valor) {
                        if (valor == null || valor.trim().isEmpty) {
                          return 'Ingresa el primer nombre.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 14),

                    // ============================================
                    // SEGUNDO NOMBRE
                    // ============================================
                    TextFormField(
                      controller: segundoNombreController,

                      enabled: !guardando,

                      textCapitalization: TextCapitalization.words,

                      decoration: _decoracionCampo(
                        etiqueta: 'Segundo nombre',

                        icono: Icons.person_outline,

                        ayuda: 'Opcional',
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ============================================
                    // APELLIDO PATERNO
                    // ============================================
                    TextFormField(
                      controller: apellidoPaternoController,

                      enabled: !guardando,

                      textCapitalization: TextCapitalization.words,

                      decoration: _decoracionCampo(
                        etiqueta: 'Apellido paterno *',

                        icono: Icons.badge_outlined,
                      ),

                      validator: (valor) {
                        if (valor == null || valor.trim().isEmpty) {
                          return 'Ingresa el apellido paterno.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 14),

                    // ============================================
                    // APELLIDO MATERNO
                    // ============================================
                    TextFormField(
                      controller: apellidoMaternoController,

                      enabled: !guardando,

                      textCapitalization: TextCapitalization.words,

                      decoration: _decoracionCampo(
                        etiqueta: 'Apellido materno *',

                        icono: Icons.badge_outlined,
                      ),

                      validator: (valor) {
                        if (valor == null || valor.trim().isEmpty) {
                          return 'Ingresa el apellido materno.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 14),

                    // ============================================
                    // RUT
                    // ============================================
                    TextFormField(
                      controller: rutController,

                      enabled: !guardando,

                      keyboardType: TextInputType.text,

                      inputFormatters: [RutInputFormatter()],

                      decoration: _decoracionCampo(
                        etiqueta: 'RUT *',

                        icono: Icons.credit_card_outlined,

                        ayuda: 'Ej.: 19.598.642-8',
                      ),

                      validator: (valor) {
                        if (valor == null || valor.trim().isEmpty) {
                          return 'Ingresa el RUT.';
                        }

                        if (!validarRut(valor)) {
                          return 'El RUT ingresado no es válido.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'Datos de acceso',

                      style: TextStyle(
                        fontSize: 21,

                        fontWeight: FontWeight.bold,

                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ============================================
                    // CORREO
                    // ============================================
                    TextFormField(
                      controller: correoController,

                      enabled: !guardando,

                      keyboardType: TextInputType.emailAddress,

                      decoration: _decoracionCampo(
                        etiqueta: 'Correo *',

                        icono: Icons.email_outlined,
                      ),

                      validator: (valor) {
                        if (valor == null || valor.trim().isEmpty) {
                          return 'Ingresa el correo.';
                        }

                        if (!correoValido(valor.trim())) {
                          return 'Ingresa un correo válido.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 24),

                    // ============================================
                    // ROL
                    // ============================================
                    const Text(
                      'Rol del usuario *',

                      style: TextStyle(
                        fontSize: 17,

                        fontWeight: FontWeight.bold,

                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 10),

                    DropdownButtonFormField<String>(
                      value: rolSeleccionado,

                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.manage_accounts_outlined),

                        filled: true,

                        fillColor: Colors.white,

                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),

                      items: roles.map((rol) {
                        return DropdownMenuItem<String>(
                          value: rol,

                          child: Text(rol),
                        );
                      }).toList(),

                      onChanged: guardando
                          ? null
                          : (valor) {
                              if (valor == null) {
                                return;
                              }

                              setState(() {
                                rolSeleccionado = valor;
                              });
                            },
                    ),

                    // ============================================
                    // ADVERTENCIA SUPERVISOR JEFE
                    // ============================================
                    if (rolSeleccionado == 'Supervisor Jefe') ...[
                      const SizedBox(height: 14),

                      Container(
                        width: double.infinity,

                        padding: const EdgeInsets.all(14),

                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),

                          borderRadius: BorderRadius.circular(12),
                        ),

                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Icon(
                              Icons.warning_amber_outlined,

                              color: Color(0xFFD97706),
                            ),

                            SizedBox(width: 10),

                            Expanded(
                              child: Text(
                                'RegiServ permite un solo Supervisor Jefe activo. El sistema validará esta condición antes de guardar.',

                                style: TextStyle(
                                  color: Color(0xFF92400E),

                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 28),

                    // ============================================
                    // GUARDAR
                    // ============================================
                    SizedBox(
                      width: double.infinity,

                      height: 54,

                      child: ElevatedButton(
                        onPressed: guardando ? null : guardarCambios,

                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),

                          foregroundColor: Colors.white,

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),

                        child: guardando
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,

                                children: [
                                  SizedBox(
                                    width: 20,

                                    height: 20,

                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,

                                      color: Colors.white,
                                    ),
                                  ),

                                  SizedBox(width: 12),

                                  Text('Guardando cambios...'),
                                ],
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,

                                children: [
                                  Icon(Icons.save_outlined),

                                  SizedBox(width: 8),

                                  Text(
                                    'Guardar cambios',

                                    style: TextStyle(
                                      fontSize: 16,

                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
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

  // =============================================================
  // DECORACIÓN
  // =============================================================

  InputDecoration _decoracionCampo({
    required String etiqueta,
    required IconData icono,
    String? ayuda,
  }) {
    return InputDecoration(
      labelText: etiqueta,

      helperText: ayuda,

      prefixIcon: Icon(icono),

      filled: true,

      fillColor: Colors.white,

      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
