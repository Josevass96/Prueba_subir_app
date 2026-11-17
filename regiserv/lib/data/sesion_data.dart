class SesionData {
  static Map<String, dynamic>? _usuarioActual;

  // =============================================================
  // USUARIO ACTUAL
  // =============================================================

  static Map<String, dynamic>? get usuarioActual {
    return _usuarioActual;
  }

  static String? get usuarioIdActual {
    return _usuarioActual?['id_usuario']?.toString();
  }

  // =============================================================
  // INICIAR SESIÓN DESDE SUPABASE
  // =============================================================

  static void iniciarSesionDesdeSupabase({
    required Map<String, dynamic> perfil,
    required String rol,
  }) {
    final primerNombre =
        (perfil['p_nombre'] ?? '').toString().trim();

    final segundoNombre =
        (perfil['s_nombre'] ?? '').toString().trim();

    final apellidoPaterno =
        (perfil['apellido_pater'] ?? '').toString().trim();

    final apellidoMaterno =
        (perfil['apellido_mater'] ?? '').toString().trim();

    final partesNombre = [
      primerNombre,
      segundoNombre,
      apellidoPaterno,
      apellidoMaterno,
    ].where(
      (parte) => parte.isNotEmpty,
    ).toList();

    final nombreCompleto =
        partesNombre.join(' ');

    _usuarioActual = {
      ...perfil,

      // ---------------------------------------------------------
      // COMPATIBILIDAD CON LAS PÁGINAS DEL PROTOTIPO
      // ---------------------------------------------------------

      'id': perfil['id_usuario'],

      'nombre': nombreCompleto,

      'primerNombre': primerNombre,

      'segundoNombre': segundoNombre,

      'apellidoPaterno': apellidoPaterno,

      'apellidoMaterno': apellidoMaterno,

      'correo': perfil['email'],

      'rol': rol,
    };
  }

  // =============================================================
  // CERRAR SESIÓN LOCAL
  // =============================================================

  static void cerrarSesion() {
    _usuarioActual = null;
  }

  // =============================================================
  // NOMBRE
  // =============================================================

  static String get nombreActual {
    return (_usuarioActual?['nombre'] ?? '')
        .toString();
  }

  static String get primerNombreActual {
    return (_usuarioActual?['primerNombre'] ?? '')
        .toString();
  }

  static String get inicialActual {
    final nombre =
        primerNombreActual.trim();

    if (nombre.isEmpty) {
      return '?';
    }

    return nombre
        .substring(0, 1)
        .toUpperCase();
  }

  // =============================================================
  // ROL
  // =============================================================

  static String get rolActual {
    return (_usuarioActual?['rol'] ?? '')
        .toString();
  }

  static bool get esAuxiliar {
    return rolActual == 'Auxiliar';
  }

  static bool get esSupervisor {
    return rolActual == 'Supervisor';
  }

  static bool get esSupervisorJefe {
    return rolActual == 'Supervisor Jefe';
  }

  static bool get esMantencion {
    return rolActual == 'Mantención';
  }
}