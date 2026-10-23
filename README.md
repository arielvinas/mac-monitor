# mac-monitor

Mini clon de iStat Menus 7: muestra el uso de **CPU**, **RAM** y **red** en la barra de menús de macOS.

- Tres ítems en la barra, estilo iStat: `MEM 56%` y `CPU 9%` (etiqueta arriba, valor abajo) y la red
  con salida `↑ 27 KB/s` arriba y entrada `↓ 6.9 MB/s` abajo.
- Clic en **CPU**: gráfico histórico (usuario/sistema), anillos por núcleo agrupados por tipo
  (eficiencia/rendimiento/super) y top 5 de procesos por CPU.
- Clic en **MEM**: anillos de presión y de memoria (Apps/Wired/Comprimida), desglose en GB y
  top 5 de procesos por memoria (footprint, igual que Monitor de Actividad).
- Clic en **red**: gráfico histórico (entrada hacia arriba, salida hacia abajo, escala automática), totales
  desde que se abrió la app y top 5 de procesos por tráfico (vía `nettop`, sólo mientras el popover está abierto).
  Se miden las interfaces físicas (`en*`), así el tráfico de VPN o VMs no se cuenta dos veces.
- Los procesos de un mismo `.app` se agrupan (p. ej. todos los helpers de Chrome suman en "Google Chrome").
- Opción "Al iniciar" para abrirlo al iniciar sesión.

## Instalar

Requiere macOS 13 o posterior (Apple Silicon o Intel). En una terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/arielvinas/mac-monitor/main/install.sh | zsh
```

Descarga el último [release](https://github.com/arielvinas/mac-monitor/releases/latest), lo copia a
`/Applications` y lo abre. La app no está notarizada por Apple; si la bajás a mano desde el release
y macOS no la deja abrir, corré `xattr -dr com.apple.quarantine /Applications/MacMonitor.app`.

## Compilar

Requiere las Command Line Tools de Xcode (`xcode-select --install`).

```sh
./build.sh            # genera build/MacMonitor.app
./build.sh --install  # además lo copia a /Applications y lo abre
./build.sh --zip      # además genera build/MacMonitor.zip para subir a un release
```

Para publicar una versión: subir `CFBundleShortVersionString` en `Info.plist`, `./build.sh --zip` y
`gh release create vX.Y build/MacMonitor.zip`.

## Depuración

```sh
build/MacMonitor.app/Contents/MacOS/MacMonitor --open cpu        # abre el popover al iniciar (cpu|mem|net)
build/MacMonitor.app/Contents/MacOS/MacMonitor --snapshot /tmp   # guarda los popovers como PNG y sale
```
