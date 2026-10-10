<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/es/hero-dark.png">
  <img src="../images/es/hero-light.png" alt="Nictate. Copia el texto que ves. La app enmarca cuatro líneas de una nota; el menú ofrece el color y el enlace que encontró, y una notificación dice Texto copiado.">
</picture>

<p align="center">
  <a href="https://github.com/jrthormann/Nictate/actions/workflows/ci.yml"><img src="https://github.com/jrthormann/Nictate/actions/workflows/ci.yml/badge.svg?branch=main" alt="Estado de CI"></a>
  <a href="https://github.com/jrthormann/Nictate/releases"><img src="https://img.shields.io/github/v/release/jrthormann/Nictate?include_prereleases&label=versi%C3%B3n" alt="Última versión"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/github/license/jrthormann/Nictate" alt="Licencia MIT"></a>
</p>

<p align="center">
  Gratis y de código abierto. Funciona en macOS 14 o posterior.
  <br>
  <a href="../../releases/latest">Descargar&nbsp;&rsaquo;</a>
  &nbsp;&nbsp;
  <a href="#compilar-desde-el-código">Compilarla tú mismo&nbsp;&rsaquo;</a>
  <br><br>
  Hecha en República Dominicana <img src="../images/flag-do.svg" width="16" height="16" alt="" align="absmiddle">, con Coke Zero y pizza como combustible.
  <br><br>
  <a href="../../README.md">English</a>&nbsp;·&nbsp;Español
</p>

<br>

## Seleccionas. Copias. Sigues.

Hay texto en tu pantalla que no te deja copiarlo. Nictate lo agarra por ti.

Pulsa <kbd>⇧</kbd>&thinsp;<kbd>⌘</kbd>&thinsp;<kbd>2</kbd> y arrastra sobre lo que tenga letras: una página web, la
foto de una pizarra, un video en pausa, una diapositiva que alguien comparte. En una fracción de segundo, el texto
ya está en tu portapapeles.

Todo ocurre en tu Mac, con el framework Vision de Apple, en cualquier idioma que Vision lea. No se sube nada.
Tus otros problemas, lamentablemente, siguen siendo tuyos.

<br>

## Píxel a píxel.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/es/bento-dark.png">
  <img src="../images/es/bento-light.png" alt="Seleccionas. Copiado. Píxel a píxel. Colores, enlaces, códigos. Nunca sale de tu Mac.">
</picture>

<br>
<br>

La selección encaja en píxeles enteros de la pantalla, así que cada borde cae justo donde lo pusiste. Las flechas
mueven la esquina un píxel cada vez, y Mayús con una flecha la mueve diez. Funciona igual que la herramienta de
capturas de pantalla del sistema, así que te va a sonar.

<br>

## Sabe lo que lee.

Nictate distingue código, tablas, listas y texto corrido, y deja cada uno como estaba escrito. El código conserva
sus saltos de línea y su sangría. Las tablas se pegan con tabuladores entre las celdas, así que caen directo en una
hoja de cálculo. Solo el texto corrido se une en párrafos, para que una lista nunca se convierta en una oración.

Los colores, enlaces, correos y teléfonos de tu última captura están a un clic en el menú. Los códigos QR y de
barras copian su contenido. Un enlace dentro de uno se copia, o se abre solo después de que confirmes la dirección,
como prefieras.

<br>

## Atajos

| Atajo | Qué hace |
|:--|:--|
| <kbd>⇧</kbd>&thinsp;<kbd>⌘</kbd>&thinsp;<kbd>2</kbd> | Selecciona un área y copia su texto. |
| <kbd>⌥</kbd>&thinsp;<kbd>⇧</kbd>&thinsp;<kbd>⌘</kbd>&thinsp;<kbd>2</kbd> | Recorre tus capturas recientes. |
| Flechas, o <kbd>⇧</kbd> con una flecha | Mueve la esquina de la selección un píxel, o diez. |
| <kbd>Return</kbd> | Empieza una esquina desde el teclado; pulsa otra vez para copiar. |
| <kbd>Esc</kbd> | Cancela la selección. |

Puedes cambiar cualquier atajo en Ajustes. Todos necesitan <kbd>⌘</kbd> o <kbd>⌃</kbd>, así que escribir normal nunca
dispara una captura por accidente. El atajo solo para códigos es opcional.

<br>

## Privado por diseño.

Sin cuenta y sin analíticas. Si activas Guardar capturas, las 15 más recientes se guardan en un archivo normal dentro
de tu Mac. Nictate no cifra ese archivo, así que desactiva el guardado o borra el archivo cuando quieras.

Nictate no hace peticiones de red por su cuenta, salvo Comprobar actualizaciones, y solo cuando tú lo pides. Un enlace
que decides abrir pasa a tu navegador, que se conecta como siempre.

<br>

## Especificaciones

| | |
|:--|:--|
| **Compatibilidad** | macOS 14 Sonoma o posterior, en Apple silicon e Intel. Diseñada para macOS 27. |
| **Tamaño** | Unos 4 MB |
| **Idiomas** | Inglés y español. El texto se reconoce en cualquier idioma que Vision admita. |
| **Hecha con** | Swift, AppKit, SwiftUI, Vision y ScreenCaptureKit |
| **Acceso a la red** | Solo Comprobar actualizaciones, y solo cuando lo pides. Los enlaces se abren en tu navegador solo si los eliges. |
| **Precio** | Gratis |
| **Licencia** | MIT |

<br>

## Estado

Nictate 1.0.0-beta.1 es una versión de prueba pública. Funciona, y la probé en macOS 27. Todavía no la he probado en
macOS 14, 15 ni 26, y VoiceOver no ha pasado por una auditoría. Los reportes son bienvenidos. El
[CHANGELOG](../../CHANGELOG.md) dice qué está probado y qué no.

## Instalación

Descarga la imagen de disco de la [última versión](../../releases/latest), ábrela y arrastra Nictate a Aplicaciones.
Nictate está firmada con un certificado local y no está notarizada, así que macOS te pide una vez que confirmes que
quieres abrirla:

- **macOS 15 o posterior:** abre Ajustes del Sistema, ve a **Privacidad y seguridad** y pulsa **Abrir igualmente** junto al aviso sobre Nictate.
- **macOS 14:** haz clic con Control en Nictate, elige **Abrir** y luego **Abrir** otra vez.

La primera vez, una ventana de bienvenida pide el permiso de **Grabación de pantalla**. Concédelo y reinicia Nictate
desde esa ventana. macOS aplica el permiso solo a una app recién abierta.

<br>

## Compilar desde el código

Necesitas macOS 14 o posterior y las herramientas de línea de comandos (`xcode-select --install`). No necesitas Xcode.

```sh
git clone https://github.com/jrthormann/Nictate.git
cd Nictate
make install
```

`make install` compila la app, la copia a Aplicaciones y la abre. `make check` ejecuta las pruebas.

<br>

## Apoya el proyecto

Si Nictate te ahorra tiempo, puedes apoyarlo con Buy Me a Coffee o PayPal. Es totalmente opcional, y lo que llegue
sirve para el mantenimiento, las mejoras y lo que venga después.

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-jrthormann-FFDD00?logo=buymeacoffee&logoColor=000000)](https://www.buymeacoffee.com/jrthormann)
[![PayPal](https://img.shields.io/badge/PayPal-jrthormann-00457C?logo=paypal&logoColor=FFFFFF)](https://paypal.me/jrthormann)

<br>

## Contribuir

Los reportes, las ideas y las pull requests son bienvenidos. [CONTRIBUTING.md](../../CONTRIBUTING.md) explica cómo
reportar un error, proponer un cambio, compilar, ejecutar las pruebas y enviar una pull request. Las traducciones
están en `Sources/Nictate/Resources/`, una carpeta `.lproj` por idioma; `make strings` se asegura de que no falte
ninguna. [docs/ARCHITECTURE.md](../ARCHITECTURE.md) explica cada archivo. La última versión de prueba está en la
página de [Releases](../../releases/latest).

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
  <sub>🇩🇴 Hecha en República Dominicana. Funciona con Coke Zero, pizza y decisiones de vida cuestionables. Si funciona, es una función. Si falla, es de código abierto.</sub>
</p>
