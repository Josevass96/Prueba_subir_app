import 'package:flutter/services.dart';

// =================================================================
// FORMATEADOR DE RUT
// =================================================================
//
// Permite que el usuario escriba solamente números y K.
// El sistema agrega automáticamente puntos y guion.
//
// Ejemplo:
// 195986428 -> 19.598.642-8
//
// También permite RUT cuyo dígito verificador sea K.

class RutInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Eliminamos puntos, guiones, espacios y cualquier otro símbolo.
    String rut = newValue.text
        .replaceAll(
          RegExp(r'[^0-9kK]'),
          '',
        )
        .toUpperCase();

    // Máximo:
    // 8 dígitos de cuerpo + 1 dígito verificador.
    if (rut.length > 9) {
      rut = rut.substring(0, 9);
    }

    final rutFormateado =
        formatearRut(rut);

    return TextEditingValue(
      text: rutFormateado,

      selection:
          TextSelection.collapsed(
        offset:
            rutFormateado.length,
      ),
    );
  }
}

// =================================================================
// FORMATEAR RUT
// =================================================================

String formatearRut(String valor) {
  String rut = valor
      .replaceAll(
        RegExp(r'[^0-9kK]'),
        '',
      )
      .toUpperCase();

  if (rut.isEmpty) {
    return '';
  }

  // Si solo existe un carácter todavía,
  // no tenemos cuerpo + dígito verificador.
  if (rut.length == 1) {
    return rut;
  }

  final digitoVerificador =
      rut.substring(
    rut.length - 1,
  );

  String cuerpo = rut.substring(
    0,
    rut.length - 1,
  );

  // Agregamos los puntos de miles.
  final caracteres =
      cuerpo.split('').reversed.toList();

  final resultado =
      <String>[];

  for (int i = 0;
      i < caracteres.length;
      i++) {
    if (i > 0 && i % 3 == 0) {
      resultado.add('.');
    }

    resultado.add(
      caracteres[i],
    );
  }

  cuerpo = resultado
      .reversed
      .join();

  return '$cuerpo-$digitoVerificador';
}

// =================================================================
// VALIDAR RUT
// =================================================================
//
// Valida matemáticamente el dígito verificador.
//
// Ejemplo:
//
// validarRut('19.598.642-8')
//
// devuelve:
// true o false

bool validarRut(String valor) {
  String rut = valor
      .replaceAll(
        RegExp(r'[^0-9kK]'),
        '',
      )
      .toUpperCase();

  // Debe existir cuerpo + dígito verificador.
  if (rut.length < 2) {
    return false;
  }

  final digitoIngresado =
      rut.substring(
    rut.length - 1,
  );

  final cuerpoTexto =
      rut.substring(
    0,
    rut.length - 1,
  );

  final cuerpo =
      int.tryParse(cuerpoTexto);

  if (cuerpo == null) {
    return false;
  }

  int suma = 0;
  int multiplicador = 2;

  // Recorremos el cuerpo del RUT
  // desde derecha hacia izquierda.
  for (int i =
          cuerpoTexto.length - 1;
      i >= 0;
      i--) {
    final numero =
        int.parse(
      cuerpoTexto[i],
    );

    suma +=
        numero *
        multiplicador;

    multiplicador++;

    // El multiplicador va de 2 a 7.
    if (multiplicador > 7) {
      multiplicador = 2;
    }
  }

  final resto =
      suma % 11;

  final resultado =
      11 - resto;

  String digitoCalculado;

  if (resultado == 11) {
    digitoCalculado = '0';
  } else if (resultado == 10) {
    digitoCalculado = 'K';
  } else {
    digitoCalculado =
        resultado.toString();
  }

  return digitoCalculado ==
      digitoIngresado;
}