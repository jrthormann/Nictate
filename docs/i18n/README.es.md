<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/es/hero-dark.png">
  <img src="../images/es/hero-light.png" alt="Nictate. Copia el texto que ves. La app enmarca cuatro líneas de una nota; el menú ofrece el color y el enlace que encontró, y una notificación dice Texto copiado.">
</picture>

<p align="center">
  Gratis y de código abierto. Para macOS 14 o posterior.
  <br>
  <a href="../../releases/latest">Descargar&nbsp;&rsaquo;</a>
  &nbsp;&nbsp;
  <a href="#compilar-desde-el-código">Compilar desde el código&nbsp;&rsaquo;</a>
  <br><br>
  Hecho en República Dominicana <img src="../images/flag-do.svg" width="16" height="16" alt="" align="absmiddle">, con Coke Zero y pizza como combustible.
  <br><br>
  <a href="../../README.md">English</a>&nbsp;·&nbsp;Español
</p>

<br>

## Selecciona. Copia. Sigue.

Tu pantalla está llena de texto que no puedes copiar. Nictate lo arregla.

Pulsa <kbd>⇧</kbd>&thinsp;<kbd>⌘</kbd>&thinsp;<kbd>2</kbd> y arrastra sobre cualquier texto de la pantalla: una
página web, una foto de una pizarra, un vídeo en pausa, una diapositiva que alguien comparte. El texto ya está en el
portapapeles antes de que termines la frase que estabas escribiendo.

El reconocimiento se hace en tu Mac con el framework Vision de Apple, en todos los idiomas que Vision admite.
No se sube nada y nada espera a un servidor. Tus otros problemas, por desgracia, quedan fuera del alcance de este proyecto.

<br>

## Píxel a píxel.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/es/bento-dark.png">
  <img src="../images/es/bento-light.png" alt="Seleccionas. Copiado. Píxel a píxel. Colores, enlaces, códigos. Nunca sale de tu Mac.">
</picture>

<br>
<br>

La selección encaja en píxeles enteros de la pantalla, así que cada borde cae exactamente donde lo pusiste.
Las flechas mueven la esquina un píxel cada vez. Con Mayúsculas, diez. Si conoces la herramienta de capturas de
pantalla.

<br>

## Sabe lo que lee.

Nictate distingue código, tablas, listas y prosa, y conserva cada una como estaba escrita. El código mantiene
todos sus saltos de línea y su sangría. Las tablas salen con tabuladores entre celdas, listas para una hoja de
cálculo. Solo la prosa normal se une en párrafos, así que una lista nunca se convierte en una frase.

Los colores, enlaces, correos y teléfonos de la última captura están a un clic en el menú. Los códigos QR y de
barras copian su contenido. Un enlace dentro de uno se copia, o se abre solo después de que confirmes su
dirección, como elijas.

<br>

## Teclas

| Teclas | Qué hace |
|:--|:--|
| <kbd>⇧</kbd>&thinsp;<kbd>⌘</kbd>&thinsp;<kbd>2</kbd> | Selecciona un área y copia su texto. |
| <kbd>⌥</kbd>&thinsp;<kbd>⇧</kbd>&thinsp;<kbd>⌘</kbd>&thinsp;<kbd>2</kbd> | Recorre las capturas recientes. |
| Flechas, <kbd>⇧</kbd> con una flecha | Mueve la esquina de la selección un píxel, o diez. |
| <kbd>Return</kbd> | Empieza una esquina desde el teclado; púlsalo otra vez para copiar. |
| <kbd>Esc</kbd> | Cancela la selección. |

Cada atajo se puede cambiar en Ajustes. Un atajo solo funciona con <kbd>⌘</kbd> o <kbd>⌃</kbd>, así que escribir
normal nunca dispara una captura por error. Un atajo solo para códigos es opcional.

<br>

## Privado por diseño.

Sin cuenta. Sin analíticas. Tu historial es un archivo en tu Mac, sin cifrado adicional, con las 15 capturas más recientes. Puedes desactivarlo o borrarlo cuando quieras. Nictate no hace peticiones de red por su cuenta, salvo Comprobar actualizaciones, que solo se ejecuta cuando lo pides. Un enlace que elijas abrir se entrega a tu navegador, que se conecta como lo haría normalmente.

<br>

## Especificaciones

| | |
|:--|:--|
| **Compatibilidad** | macOS 14 Sonoma o posterior, en Apple silicon e Intel. Diseñado para macOS 27. |
| **Tamaño** | Unos 4 MB |
| **Idiomas** | Inglés y español. El texto se reconoce en todos los idiomas que admite Vision. |
| **Hecho con** | Swift, AppKit, SwiftUI, Vision y ScreenCaptureKit |
| **Acceso a la red** | Solo Comprobar actualizaciones, cuando lo pides. Los enlaces se abren en tu navegador solo si los eliges. |
| **Precio** | Gratis |
| **Licencia** | MIT |

<br>

## Instalación

Descarga la imagen de disco de la [última versión](../../releases/latest), ábrela y arrastra Nictate a
Aplicaciones. Nictate está firmada con un certificado local y no está notarizada, así que macOS te pide una vez
que confirmes que quieres abrirla:

- **macOS 15 y posteriores:** abre Ajustes del Sistema, ve a **Privacidad y seguridad** y pulsa **Abrir igualmente** junto al aviso sobre Nictate.
- **macOS 14:** haz clic con Control en Nictate, elige **Abrir** y luego **Abrir** otra vez.

La primera vez, una ventana de bienvenida pide el permiso de **Grabación de pantalla**. Concédelo y reinicia
Nictate desde esa ventana. macOS aplica el permiso solo a una app recién abierta.

<br>

## Compilar desde el código

Necesitas macOS 14 o posterior y las herramientas de línea de comandos (`xcode-select --install`). No hace falta Xcode.

```sh
git clone https://github.com/jrthormann/Nictate.git
cd Nictate
make install
```

`make install` compila la app, la copia a Aplicaciones y la abre. Las comprobaciones se ejecutan con `make check`.

<br>

## Contribuir

Las incidencias y las pull requests son bienvenidas. Las traducciones están en `Sources/Nictate/Resources/`, una carpeta
`.lproj` por idioma; `make strings` comprueba que no falte ninguna. [docs/ARCHITECTURE.md](../ARCHITECTURE.md)
explica qué hace cada archivo.

<br>

---

<sub>
Nictate se distribuye bajo la licencia MIT; ver <a href="../../LICENSE">LICENSE</a>. Solo usa frameworks del sistema
de Apple y, si lo pides, la lista pública de versiones de GitHub para Comprobar actualizaciones. Las notas de cada
versión están en <a href="../../CHANGELOG.md">CHANGELOG.md</a>.
</sub>

<br>
<br>

<p align="center">
  <img src="../images/icon.png" width="64" height="64" alt="">
  <br>
  <sub>Copia el texto que ves. Sin nube, sin rastreo, sin tonterías.</sub>
  <br><br>
  <sub>🇩🇴 Built in the Dominican Republic. Runs on Coke Zero, pizza, and questionable life choices. If it works, it's a feature. If it breaks, it's open source.</sub>
</p>
