# mac-monitor

Mini clon de iStat Menus 7: muestra el uso de **CPU** y **RAM** en la barra de menús de macOS.

- Dos ítems en la barra, estilo iStat: `MEM 56%` y `CPU 9%` (etiqueta arriba, valor abajo).
- Clic en **CPU**: gráfico histórico (usuario/sistema), anillos por núcleo agrupados por tipo
  (eficiencia/rendimiento/super) y top 5 de procesos por CPU.
- Clic en **MEM**: anillos de presión y de memoria (Apps/Wired/Comprimida), desglose en GB y
  top 5 de procesos por memoria (footprint, igual que Monitor de Actividad).
- Los procesos de un mismo `.app` se agrupan (p. ej. todos los helpers de Chrome suman en "Google Chrome").
- Opción "Al iniciar" para abrirlo al iniciar sesión.

## Compilar

Requiere las Command Line Tools de Xcode (`xcode-select --install`).

```sh
./build.sh            # genera build/MacMonitor.app
./build.sh --install  # además lo copia a /Applications y lo abre
```

## Depuración

```sh
build/MacMonitor.app/Contents/MacOS/MacMonitor --open cpu        # abre el popover al iniciar (cpu|mem)
build/MacMonitor.app/Contents/MacOS/MacMonitor --snapshot /tmp   # guarda los popovers como PNG y sale
```
