#!/usr/bin/env python3
"""Genera el versiones.json de un himnario: la huella y el tamaño de cada hoja.

La app lo compara con lo que tiene guardado para saber qué hojas cambiaron.
Cada himnario tiene el suyo (assets/himnarios/<himnario>/versiones.json) y
GitHub Actions lo regenera en cada publicación (ver .github/workflows/deploy.yml),
así que no hay que editarlo a mano: basta con reemplazar la imagen.
Solo cuentan las hojas ("34-1", o "2-2_3-1" si la hoja trae dos himnos); la portada no.

Uso: python3 tool/generar_versiones.py <carpeta_del_himnario> <archivo_salida>
Ej.: python3 tool/generar_versiones.py assets/himnarios/ministerio assets/himnarios/ministerio/versiones.json
"""
import hashlib
import json
import re
import sys
from pathlib import Path

carpeta, salida = Path(sys.argv[1]), Path(sys.argv[2])
archivos = {}
HOJA = re.compile(r'^\d+-\d+(?:_\d+-\d+)*$')
for imagen in sorted(carpeta.glob('*.webp')):
    if not HOJA.match(imagen.stem):
        continue
    datos = imagen.read_bytes()
    archivos[imagen.stem] = {
        'hash': hashlib.sha256(datos).hexdigest()[:12],
        'bytes': len(datos),
    }
if not archivos:
    sys.exit(f'No se encontraron imágenes .webp en {carpeta}')

version = hashlib.sha256(json.dumps(archivos, sort_keys=True).encode()).hexdigest()[:12]
salida.write_text(json.dumps({'version': version, 'archivos': archivos},
                             sort_keys=True, separators=(',', ':')))
print(f'{salida}: {len(archivos)} hojas, versión {version}')
