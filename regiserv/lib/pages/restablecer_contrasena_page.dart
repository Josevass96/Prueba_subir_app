import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RestablecerContrasenaPage extends StatefulWidget {
  const RestablecerContrasenaPage({super.key});

  @override
  State<RestablecerContrasenaPage> createState() =>
      _RestablecerContrasenaPageState();
}

class _RestablecerContrasenaPageState extends State<RestablecerContrasenaPage> {
  final TextEditingController nuevaController = TextEditingController();

  final TextEditingController confirmarController = TextEditingController();

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  SupabaseClient get supabase => Supabase.instance.client;

  bool ocultarNueva = true;
  bool ocultarConfirmacion = true;
  bool guardando = false;

  String? mensajeError;

  bool get cumpleMayuscula => RegExp(r'[A-Z]').hasMatch(nuevaController.text);

  bool get cumpleMinuscula => RegExp(r'[a-z]').hasMatch(nuevaController.text);

  bool get cumpleNumero => RegExp(r'[0-9]').hasMatch(nuevaController.text);

  bool get cumpleEspecial =>
      RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=;]').hasMatch(nuevaController.text);

  bool get cumpleLargo => nuevaController.text.length >= 8;

  bool get cumpleTodosLosRequisitos =>
      cumpleLargo &&
      cumpleMayuscula &&
      cumpleMinuscula &&
      cumpleNumero &&
      cumpleEspecial;

  bool get confirmacionCoincide =>
      confirmarController.text.isNotEmpty &&
      confirmarController.text == nuevaController.text;

  bool get puedeGuardar =>
      cumpleTodosLosRequisitos && confirmacionCoincide && !guardando;

  @override
  void dispose() {
    nuevaController.dispose();
    confirmarController.dispose();
    super.dispose();
  }

  String? validarConfirmacion(String? valor) {
    final String confirmacion = valor ?? '';

    if (confirmacion.isEmpty) {
      return null;
    }

    if (confirmacion != nuevaController.text) {
      return 'Las contraseñas no coinciden.';
    }

    return null;
  }

  Widget requisitoContrasena({required String texto, required bool cumplido}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cumplido
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFF3F4F6),
            ),
            child: Icon(
              cumplido ? Icons.check : Icons.circle_outlined,
              size: 16,
              color: cumplido
                  ? const Color(0xFF16A34A)
                  : const Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                color: cumplido
                    ? const Color(0xFF166534)
                    : const Color(0xFF4B5563),
                fontWeight: cumplido ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> guardarNuevaContrasena() async {
    if (!puedeGuardar) {
      return;
    }

    FocusScope.of(context).unfocus();

    formKey.currentState?.validate();

    final User? usuario = supabase.auth.currentUser;

    if (usuario == null) {
      setState(() {
        mensajeError =
            'El enlace de recuperación ya no es válido o la sesión expiró. '
            'Solicita un nuevo correo de recuperación.';
      });

      return;
    }

    setState(() {
      guardando = true;
      mensajeError = null;
    });

    try {
      final UserResponse respuesta = await supabase.auth.updateUser(
        UserAttributes(password: nuevaController.text),
      );

      if (respuesta.user == null) {
        throw Exception('Supabase no confirmó el cambio de contraseña.');
      }

      // Cerramos la sesión de recuperación.
      // El usuario deberá entrar normalmente con su nueva clave,
      // permitiendo que el Login vuelva a validar activo y rol.
      await supabase.auth.signOut();

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            icon: const Icon(
              Icons.check_circle_outline,
              color: Color(0xFF16A34A),
              size: 48,
            ),
            title: const Text(
              'Contraseña restablecida',
              textAlign: TextAlign.center,
            ),
            content: const Text(
              'Tu contraseña fue actualizada correctamente. '
              'Ahora puedes iniciar sesión con tu nueva contraseña.',
              textAlign: TextAlign.center,
            ),
            actions: [
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Ir al inicio de sesión'),
                ),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }

      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    } on AuthException catch (error) {
      debugPrint(
        'ERROR RESTABLECIENDO CONTRASEÑA: '
        'code=${error.code} message=${error.message}',
      );

      if (!mounted) {
        return;
      }

      final String codigo = (error.code ?? '').toLowerCase();

      final String mensaje = error.message.toLowerCase();

      setState(() {
        if (codigo == 'same_password' ||
            mensaje.contains('different from the old password') ||
            mensaje.contains('same password')) {
          mensajeError = 'La nueva contraseña debe ser distinta de la contraseña que utilizabas anteriormente.';
        } else if (codigo == 'reauthentication_needed' ||
            mensaje.contains('reauthentication')) {
          mensajeError =
              'La sesión de recuperación ya no permite cambiar la contraseña. '
              'Solicita un nuevo correo de recuperación.';
        } else if (codigo == 'weak_password' ||
            mensaje.contains('password should')) {
          mensajeError = 'La contraseña no cumple los requisitos de seguridad configurados en Supabase.';
        } else if (codigo == 'session_not_found' ||
            codigo == 'refresh_token_not_found' ||
            mensaje.contains('expired') ||
            mensaje.contains('invalid token')) {
          mensajeError =
              'El enlace de recuperación venció o ya no es válido. '
              'Solicita un nuevo correo de recuperación.';
        } else {
          mensajeError =
              'No fue posible restablecer la contraseña. '
              'Intenta con una contraseña distinta o solicita un nuevo enlace.';
        }
      });
    } catch (error) {
      debugPrint('ERROR RESTABLECER REGISERV: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        mensajeError =
            'No fue posible restablecer la contraseña. '
            'Intenta nuevamente.';
      });
    } finally {
      if (mounted) {
        setState(() {
          guardando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,

      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),

        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: const Text(
            'Restablecer contraseña',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
        ),

        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),

              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 500),
                padding: const EdgeInsets.all(24),

                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),

                child: Form(
                  key: formKey,

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,

                    children: [
                      const Icon(
                        Icons.password_outlined,
                        size: 52,
                        color: Color(0xFF1565C0),
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'Crea una nueva contraseña',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        'El enlace de recuperación fue validado. '
                        'Define la nueva contraseña que utilizarás para ingresar a RegiServ.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
                      ),

                      const SizedBox(height: 24),

                      TextFormField(
                        controller: nuevaController,
                        enabled: !guardando,
                        obscureText: ocultarNueva,
                        textInputAction: TextInputAction.next,

                        onChanged: (_) {
                          setState(() {});

                          if (formKey.currentState != null) {
                            formKey.currentState!.validate();
                          }
                        },

                        decoration: InputDecoration(
                          labelText: 'Nueva contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: guardando
                                ? null
                                : () {
                                    setState(() {
                                      ocultarNueva = !ocultarNueva;
                                    });
                                  },
                            icon: Icon(
                              ocultarNueva
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: confirmarController,
                        enabled: !guardando,
                        obscureText: ocultarConfirmacion,
                        textInputAction: TextInputAction.done,
                        validator: validarConfirmacion,

                        onChanged: (_) {
                          setState(() {});

                          if (formKey.currentState != null) {
                            formKey.currentState!.validate();
                          }
                        },

                        onFieldSubmitted: (_) {
                          if (puedeGuardar) {
                            guardarNuevaContrasena();
                          }
                        },

                        decoration: InputDecoration(
                          labelText: 'Confirmar contraseña',
                          prefixIcon: const Icon(Icons.lock_person_outlined),
                          suffixIcon: IconButton(
                            onPressed: guardando
                                ? null
                                : () {
                                    setState(() {
                                      ocultarConfirmacion =
                                          !ocultarConfirmacion;
                                    });
                                  },
                            icon: Icon(
                              ocultarConfirmacion
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            const Text(
                              'La contraseña debe incluir:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),

                            const SizedBox(height: 8),

                            requisitoContrasena(
                              texto: 'Al menos 8 caracteres',
                              cumplido: cumpleLargo,
                            ),

                            requisitoContrasena(
                              texto: 'Una letra mayúscula',
                              cumplido: cumpleMayuscula,
                            ),

                            requisitoContrasena(
                              texto: 'Una letra minúscula',
                              cumplido: cumpleMinuscula,
                            ),

                            requisitoContrasena(
                              texto: 'Un número',
                              cumplido: cumpleNumero,
                            ),

                            requisitoContrasena(
                              texto: 'Un carácter especial (!, ., @, #, etc.)',
                              cumplido: cumpleEspecial,
                            ),
                          ],
                        ),
                      ),

                      if (mensajeError != null) ...[
                        const SizedBox(height: 16),

                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Text(
                            mensajeError!,
                            style: const TextStyle(color: Color(0xFF991B1B)),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: puedeGuardar
                              ? guardarNuevaContrasena
                              : null,

                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFD1D5DB),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),

                          child: guardando
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Guardar nueva contraseña',
                                  style: TextStyle(fontWeight: FontWeight.w600),
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
      ),
    );
  }
}
