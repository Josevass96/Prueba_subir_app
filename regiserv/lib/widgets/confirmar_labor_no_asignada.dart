import 'package:flutter/material.dart';

/// Pide autorización expresa para comenzar una labor en un espacio
/// que no está asignado al Auxiliar autenticado.
///
/// No inicia ni termina la labor, y no omite ninguna validación NFC/GPS.
/// Se invoca DESPUÉS de identificar el NFC y ANTES de iniciar la RPC.
Future<bool> confirmarLaborNoAsignada(
  BuildContext context, {
  String? nombreEspacio,
}) async {
  final String espacio = (nombreEspacio ?? '').trim();

  final bool? resultado = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Row(
          children: <Widget>[
            Icon(Icons.info_outline),
            SizedBox(width: 10),
            Expanded(child: Text('Labor no asignada')),
          ],
        ),
        content: Text(
          '${espacio.isEmpty ? 'Este espacio' : 'El espacio "$espacio"'} '
          'no está entre tus asignaciones.\n\n'
          'Si continúas, realizarás la labor con el mismo procedimiento '
          'de NFC, GPS, fotografías y observaciones.\n\n'
          'Quedará registrado para el Supervisor que la labor fue '
          'realizada por un Auxiliar no asignado.\n\n'
          '¿Deseas continuar?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      );
    },
  );

  return resultado ?? false;
}
