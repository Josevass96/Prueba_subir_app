import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecuperarContrasenaPage extends StatefulWidget {
  const RecuperarContrasenaPage({super.key});

  @override
  State<RecuperarContrasenaPage> createState() =>
      _RecuperarContrasenaPageState();
}

class _RecuperarContrasenaPageState extends State<RecuperarContrasenaPage> {
  final TextEditingController correoController = TextEditingController();

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  SupabaseClient get supabase => Supabase.instance.client;

  bool enviando = false;
  String? mensajeError;

  @override
  void dispose() {
    correoController.dispose();
    super.dispose();
  }

  bool get formularioValido {
    final correo = correoController.text.trim();

    return correo.isNotEmpty &&
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(correo);
  }

  String? validarCorreo(String? valor) {
    final correo = valor?.trim() ?? '';

    if (correo.isEmpty) {
      return null;
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(correo)) {
      return 'Ingresa un correo electrónico válido.';
    }

    return null;
  }

  String get redirectRecuperacion {
    if (kIsWeb) {
      // Durante desarrollo web, el correo volverá exactamente
      // al mismo origen donde está ejecutándose RegiServ.
      return Uri.base.origin;
    }

    // Para Android/iOS utilizaremos deep link.
    return 'regiserv://reset-password/';
  }

  Future<void> enviarRecuperacion() async {
    if (!formularioValido || enviando) {
      return;
    }

    FocusScope.of(context).unfocus();

    if (formKey.currentState?.validate() != true) {
      return;
    }

    final String correo = correoController.text.trim().toLowerCase();

    setState(() {
      enviando = true;
      mensajeError = null;
    });

    try {
      await supabase.auth.resetPasswordForEmail(
        correo,
        redirectTo: redirectRecuperacion,
      );

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            icon: const Icon(
              Icons.mark_email_read_outlined,
              color: Color(0xFF16A34A),
              size: 48,
            ),
            title: const Text('Revisa tu correo', textAlign: TextAlign.center),
            content: const Text(
              'Si existe una cuenta activa asociada a ese correo, '
              'recibirás un enlace para restablecer tu contraseña.\n\n'
              'Por seguridad, RegiServ no informa si el correo está '
              'o no registrado.',
              textAlign: TextAlign.center,
            ),
            actions: [
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Aceptar'),
                ),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(context);
    } on AuthException catch (error) {
      debugPrint('ERROR RECUPERACIÓN SUPABASE: ${error.message}');

      if (!mounted) {
        return;
      }

      setState(() {
        // Los errores de cuenta inexistente no se muestran.
        // Supabase ya evita revelar si un correo está registrado.
        if (error.message.toLowerCase().contains('rate limit') ||
            error.message.toLowerCase().contains('email rate limit')) {
          mensajeError =
              'Se han solicitado demasiados correos en poco tiempo. '
              'Intenta nuevamente más tarde.';
        } else {
          mensajeError =
              'No fue posible enviar las instrucciones en este momento. '
              'Revisa tu conexión e intenta nuevamente.';
        }
      });
    } catch (error) {
      debugPrint('ERROR RECUPERACIÓN REGISERV: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        mensajeError =
            'No fue posible enviar las instrucciones en este momento. '
            'Revisa tu conexión e intenta nuevamente.';
      });
    } finally {
      if (mounted) {
        setState(() {
          enviando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,

        title: const Text(
          'Recuperar contraseña',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),

          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),

              child: Form(
                key: formKey,

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    const SizedBox(height: 20),

                    const Icon(
                      Icons.lock_reset,
                      size: 54,
                      color: Color(0xFF1565C0),
                    ),

                    const SizedBox(height: 20),

                    const Text(
                      '¿Olvidaste tu contraseña?',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'Ingresa el correo asociado a tu cuenta. '
                      'Te enviaremos un enlace para recuperar el acceso.',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: Color(0xFF6B7280),
                      ),
                    ),

                    const SizedBox(height: 30),

                    TextFormField(
                      controller: correoController,
                      enabled: !enviando,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      validator: validarCorreo,

                      onChanged: (_) {
                        setState(() {
                          mensajeError = null;
                        });
                      },

                      onFieldSubmitted: (_) {
                        if (formularioValido && !enviando) {
                          enviarRecuperacion();
                        }
                      },

                      decoration: InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                    if (mensajeError != null) ...[
                      const SizedBox(height: 16),

                      Container(
                        width: double.infinity,
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
                      width: double.infinity,
                      height: 54,

                      child: ElevatedButton(
                        onPressed: formularioValido && !enviando
                            ? enviarRecuperacion
                            : null,

                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFD1D5DB),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),

                        child: enviando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Enviar instrucciones',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
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
}
