# Instalar Nictate

[English](../INSTALL.md) · Español · [Volver al README](../../docs/i18n/README.es.md)

Descarga la imagen de disco solo desde la [página de versiones](https://github.com/jrthormann/Nictate/releases). Ábrela y arrastra Nictate a Aplicaciones. La versión actual es la 1.0.0-beta.2, así que esa es la que toca descargar.

**Nictate no está notarizada por Apple.** Está firmada con un certificado local, así que macOS te pide aprobarla una vez, antes de la primera apertura. Es una limitación conocida de esta beta. No necesitas desactivar Gatekeeper ni ninguna otra protección de seguridad del sistema para abrir Nictate. Aprobar Nictate una vez solo afecta a Nictate.

1. Abre **Aplicaciones** y haz doble clic en **Nictate**.
2. macOS muestra un aviso de que Apple no pudo verificar Nictate. Ciérralo con su botón de descartar, y no elijas la opción de mover la app a la papelera. El texto exacto depende de tu versión de macOS.
3. Abre **Ajustes del Sistema**, ve a **Privacidad y seguridad** y baja hasta **Seguridad**. Pulsa **Abrir igualmente** junto al aviso sobre Nictate, y luego escribe tu contraseña o usa Touch ID.
4. Abre Nictate otra vez. Si macOS pide confirmarlo, pulsa **Abrir**.
5. La ventana de bienvenida pide **Permite la grabación de pantalla**. Pulsa **Abrir Ajustes del Sistema**, activa Nictate en la lista de grabación de pantalla de Ajustes del Sistema, y pulsa **Reiniciar Nictate** en la ventana de bienvenida.
6. Selecciona texto con <kbd>⇧</kbd>&thinsp;<kbd>⌘</kbd>&thinsp;<kbd>2</kbd>, y se copia en tu portapapeles.

**En macOS 14 Sonoma**, usa esto en lugar de los pasos 2 a 4: haz clic con Control en Nictate en Aplicaciones, elige **Abrir** y luego pulsa **Abrir** otra vez. Después sigue con el paso 5.

**Sobre la firma.** Una firma de código válida permite a macOS confirmar que la app es la misma que se compiló, y que la firmó el certificado local de Nictate. No es una firma Apple Developer ID, y Apple no ha notarizado ni verificado Nictate. Por eso macOS te pide aprobarla.

**Permisos.** Nictate necesita la Grabación de pantalla para leer el texto de tu pantalla. No usa acceso de Accesibilidad. La primera vez que Nictate tenga algo que avisarte, macOS puede preguntarte si quieres permitir notificaciones. Es opcional, y Nictate funciona sin ellas.

**Suma de verificación (opcional).** Cada versión indica la suma SHA-256 de su imagen de disco. Puedes compararla con tu descarga para confirmar que el archivo coincide con el publicado. Esto requiere Terminal, así que no forma parte de la instalación normal.

## Actualizar desde la beta.1

La beta.1 se identifica como versión 1.0.0, así que su comprobación de actualizaciones no ve las versiones nuevas. Si tienes la beta.1, descarga la beta.2 desde la [página de versiones](https://github.com/jrthormann/Nictate/releases) y reemplaza la app en Aplicaciones.
