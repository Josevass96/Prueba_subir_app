import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CambiarContrasenaPage extends StatefulWidget {
  final String contrasenaActual;

  const CambiarContrasenaPage({super.key, required this.contrasenaActual});

  @override
  State<CambiarContrasenaPage> createState() => _CambiarContrasenaPageState();
}

class _CambiarContrasenaPageState extends State<CambiarContrasenaPage> {
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

  bool get esDistintaDeTemporal =>
      nuevaController.text.isNotEmpty &&
      nuevaController.text != widget.contrasenaActual;

  bool get confirmacionCoincide =>
      confirmarController.text.isNotEmpty &&
      confirmarController.text == nuevaController.text;

  bool get puedeGuardar =>
      cumpleTodosLosRequisitos &&
      esDistintaDeTemporal &&
      confirmacionCoincide &&
      !guardando;

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

  @override
  void dispose() {
    nuevaController.dispose();
    confirmarController.dispose();
    super.dispose();
  }

  String? validarNuevaContrasena(String? valor) {
    final String password = valor ?? '';

    // El checklist informa los requisitos faltantes.
    // Solo mostramos error rojo cuando intenta reutilizar
    // la contraseña temporal.
    if (password.isNotEmpty && password == widget.contrasenaActual) {
      return 'La nueva contraseña debe ser distinta de la contraseña temporal.';
    }

    return null;
  }

  String? validarConfirmacion(String? valor) {
    final String confirmacion = valor ?? '';

    // Vacío = estado neutro. Solo mostramos error cuando
    // el usuario ya escribió algo y no coincide.
    if (confirmacion.isEmpty) {
      return null;
    }

    if (confirmacion != nuevaController.text) {
      return 'Las contraseñas no coinciden.';
    }

    return null;
  }

  Future<void> cambiarContrasena() async {
    if (guardando) {
      return;
    }

    FocusScope.of(context).unfocus();

    // Revalidamos únicamente los errores específicos visibles.
    formKey.currentState?.validate();

    // El botón normalmente estará deshabilitado hasta que todo
    // esté correcto. Esta validación adicional protege el flujo.
    if (!cumpleTodosLosRequisitos ||
        !esDistintaDeTemporal ||
        !confirmacionCoincide) {
      return;
    }

    final User? usuario = supabase.auth.currentUser;

    if (usuario == null) {
      setState(() {
        mensajeError =
            'La sesión ya no está disponible. Vuelve a iniciar sesión.';
      });

      return;
    }

    setState(() {
      guardando = true;
      mensajeError = null;
    });

    try {
      final String nueva = nuevaController.text;

      final UserResponse respuesta = await supabase.auth.updateUser(
        UserAttributes(password: nueva),
      );

      if (respuesta.user == null) {
        throw Exception(
          'Supabase no confirmó la actualización de la contraseña.',
        );
      }

      final Map<String, dynamic> perfil = await supabase
          .from('usuario')
          .select(
            'primer_acceso, '
            'requiere_cambio_clave',
          )
          .eq('id_usuario', usuario.id)
          .single();

      if (perfil['requiere_cambio_clave'] == true) {
        throw Exception(
          'La contraseña cambió, pero no fue posible confirmar el estado del primer acceso.',
        );
      }

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            icon: const Icon(
              Icons.check_circle_outline,
              color: Color(0xFF16A34A),
              size: 46,
            ),
            title: const Text(
              'Contraseña actualizada',
              textAlign: TextAlign.center,
            ),
            content: const Text(
              'Tu nueva contraseña quedó guardada correctamente. '
              'Desde ahora podrás ingresar normalmente a RegiServ.',
              textAlign: TextAlign.center,
            ),
            actions: [
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Continuar'),
                ),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        mensajeError = error.message;
      });
    } catch (error, stackTrace) {
      debugPrint('ERROR CAMBIANDO CONTRASEÑA: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        mensajeError = error.toString().replaceFirst('Exception: ', '');
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
            'Cambiar contraseña',
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
                        Icons.lock_reset_outlined,
                        size: 52,
                        color: Color(0xFF1565C0),
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'Debes crear una nueva contraseña',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        'Por seguridad, la contraseña temporal solo puede utilizarse para el primer ingreso.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
                      ),

                      const SizedBox(height: 24),

                      TextFormField(
                        controller: nuevaController,
                        enabled: !guardando,
                        obscureText: ocultarNueva,
                        textInputAction: TextInputAction.next,
                        validator: validarNuevaContrasena,

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
                          if (!guardando) {
                            cambiarContrasena();
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
                          onPressed: puedeGuardar ? cambiarContrasena : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
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
