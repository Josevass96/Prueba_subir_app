import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/rut_formatter.dart';

class NuevoUsuarioPage extends StatefulWidget {
  const NuevoUsuarioPage({super.key});

  @override
  State<NuevoUsuarioPage> createState() => _NuevoUsuarioPageState();
}

class _NuevoUsuarioPageState extends State<NuevoUsuarioPage> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  final TextEditingController primerNombreController = TextEditingController();

  final TextEditingController segundoNombreController = TextEditingController();

  final TextEditingController apellidoPaternoController =
      TextEditingController();

  final TextEditingController apellidoMaternoController =
      TextEditingController();

  final TextEditingController rutController = TextEditingController();

  final GlobalKey<FormFieldState<String>> rutFieldKey =
      GlobalKey<FormFieldState<String>>();

  final FocusNode rutFocusNode = FocusNode();

  bool validarRutEnVivo = false;

  final TextEditingController correoController = TextEditingController();

  final TextEditingController contrasenaController = TextEditingController();

  String rolSeleccionado = 'Auxiliar';

  bool ocultarContrasena = true;

  bool creandoUsuario = false;

  final List<String> roles = [
    'Auxiliar',
    'Supervisor',
    'Supervisor Jefe',
    'Mantención',
  ];

  SupabaseClient get supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();

    rutFocusNode.addListener(_validarRutAlSalir);
  }

  void _validarRutAlSalir() {
    if (!rutFocusNode.hasFocus) {
      validarRutEnVivo = true;
      rutFieldKey.currentState?.validate();
    }
  }

  @override
  void dispose() {
    primerNombreController.dispose();
    segundoNombreController.dispose();
    apellidoPaternoController.dispose();
    apellidoMaternoController.dispose();
    rutController.dispose();
    correoController.dispose();
    contrasenaController.dispose();

    rutFocusNode.removeListener(_validarRutAlSalir);
    rutFocusNode.dispose();

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
  // OBTENER MENSAJE DE ERROR DE EDGE FUNCTION
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

    return 'No fue posible crear el usuario.';
  }

  // =============================================================
  // CREAR USUARIO REAL
  // =============================================================

  Future<void> crearUsuario() async {
    if (creandoUsuario) {
      return;
    }

    validarRutEnVivo = true;

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
    // CONFIRMACIÓN
    // -----------------------------------------------------------

    final confirmar = await showDialog<bool>(
      context: context,

      builder: (context) {
        return AlertDialog(
          title: const Text('Crear usuario'),

          content: Text(
            '¿Deseas crear la cuenta de '
            '${primerNombreController.text.trim()} '
            '${apellidoPaternoController.text.trim()} '
            'con rol $rolSeleccionado?',
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

              child: const Text('Crear usuario'),
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

    // -----------------------------------------------------------
    // COMENZAR PROCESO
    // -----------------------------------------------------------

    setState(() {
      creandoUsuario = true;
    });

    try {
      // =========================================================
      // INVOCAR EDGE FUNCTION
      // =========================================================

      final respuesta = await supabase.functions.invoke(
        'crear-usuario',

        headers: {'Authorization': 'Bearer ${session.accessToken}'},

        body: {
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

          'password': contrasenaController.text,

          'rol': rolSeleccionado,
        },
      );

      final data = respuesta.data;

      // ---------------------------------------------------------
      // VALIDAR RESPUESTA
      // ---------------------------------------------------------

      if (data is! Map || data['ok'] != true) {
        throw Exception('La función no confirmó la creación del usuario.');
      }

      if (!mounted) {
        return;
      }

      // ---------------------------------------------------------
      // VOLVER A GESTIÓN DE USUARIOS
      // ---------------------------------------------------------

      Navigator.pop(context, true);
    }
    // ===========================================================
    // ERROR DEVUELTO POR LA EDGE FUNCTION
    // ===========================================================
    on FunctionException catch (error) {
      debugPrint(
        'ERROR EDGE FUNCTION: '
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
      debugPrint('ERROR CREAR USUARIO: $error');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No fue posible crear el usuario. Revisa la conexión con Supabase.',
          ),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          creandoUsuario = false;
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
          'Nuevo usuario',

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
                              'La cuenta quedará activa y el usuario deberá cambiar su contraseña inicial en el primer acceso.',

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

                      enabled: !creandoUsuario,

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

                      enabled: !creandoUsuario,

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

                      enabled: !creandoUsuario,

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

                      enabled: !creandoUsuario,

                      textCapitalization: TextCapitalization.words,

                      decoration: _decoracionCampo(
                        etiqueta: 'Apellido materno',

                        icono: Icons.badge_outlined,

                        ayuda: 'Opcional',
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ============================================
                    // RUT
                    // ============================================
                    TextFormField(
                      key: rutFieldKey,

                      controller: rutController,

                      focusNode: rutFocusNode,

                      enabled: !creandoUsuario,

                      textInputAction: TextInputAction.next,

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

                      onChanged: (_) {
                        if (validarRutEnVivo) {
                          rutFieldKey.currentState?.validate();
                        }
                      },

                      onFieldSubmitted: (_) {
                        validarRutEnVivo = true;
                        rutFieldKey.currentState?.validate();

                        FocusScope.of(context).nextFocus();
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

                      enabled: !creandoUsuario,

                      keyboardType: TextInputType.emailAddress,

                      decoration: _decoracionCampo(
                        etiqueta: 'Correo *',

                        icono: Icons.email_outlined,

                        ayuda: 'usuario@correo.cl',
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

                    const SizedBox(height: 14),

                    // ============================================
                    // CONTRASEÑA
                    // ============================================
                    TextFormField(
                      controller: contrasenaController,

                      enabled: !creandoUsuario,

                      obscureText: ocultarContrasena,

                      decoration: InputDecoration(
                        labelText: 'Contraseña inicial *',

                        helperText: 'Mínimo 8 caracteres',

                        prefixIcon: const Icon(Icons.lock_outline),

                        suffixIcon: IconButton(
                          onPressed: creandoUsuario
                              ? null
                              : () {
                                  setState(() {
                                    ocultarContrasena = !ocultarContrasena;
                                  });
                                },

                          icon: Icon(
                            ocultarContrasena
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),

                        filled: true,

                        fillColor: Colors.white,

                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),

                      validator: (valor) {
                        if (valor == null || valor.isEmpty) {
                          return 'Ingresa una contraseña inicial.';
                        }

                        if (valor.length < 8) {
                          return 'La contraseña debe tener al menos 8 caracteres.';
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

                      onChanged: creandoUsuario
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
                                'RegiServ considera un solo Supervisor Jefe activo. Esta condición será controlada por las reglas administrativas del sistema.',

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
                    // CREAR
                    // ============================================
                    SizedBox(
                      width: double.infinity,

                      height: 54,

                      child: ElevatedButton(
                        onPressed: creandoUsuario ? null : crearUsuario,

                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),

                          foregroundColor: Colors.white,

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),

                        child: creandoUsuario
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

                                  Text('Creando usuario...'),
                                ],
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,

                                children: [
                                  Icon(Icons.person_add_alt_1_outlined),

                                  SizedBox(width: 8),

                                  Text(
                                    'Crear usuario',

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
  // DECORACIÓN DE CAMPOS
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
