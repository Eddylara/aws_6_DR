#!/usr/bin/env python3
"""
Monitor de Health Check + Cálculo de RTO
Proyecto 06 - Disaster Recovery Multi-Región AWS

Uso: python monitor_rto.py
"""

import requests
import time
from datetime import datetime

URL = "http://ddr5-proyecto-6.eddylara.art/health"
INTERVALO = 5  # segundos entre cada verificación


def check_health():
    try:
        r = requests.get(URL, timeout=5)
        return r.status_code == 200
    except Exception:
        return False


def formato_tiempo(segundos):
    m = int(segundos // 60)
    s = int(segundos % 60)
    if m > 0:
        return f"{m} min {s} seg ({int(segundos)} seg)"
    return f"{s} seg"


def ahora():
    return datetime.now().strftime("%H:%M:%S")


def main():
    print("=" * 55)
    print("   MONITOR DE HEALTH CHECK + CÁLCULO DE RTO")
    print(f"   URL: {URL}")
    print(f"   Intervalo de verificación: {INTERVALO}s")
    print("=" * 55)

    # ── Esperar a que el sistema esté UP antes de empezar ──
    print("\nVerificando estado inicial...")
    while not check_health():
        print(f"  [{ahora()}] Sistema caído o no disponible. Esperando...")
        time.sleep(INTERVALO)

    print(f"  [{ahora()}] ✓ Sistema UP. Monitoreando...\n")
    print("  Provoca la caída desde la consola AWS cuando quieras.")
    print("  El monitor detectará la caída y calculará el RTO.\n")
    print("-" * 55)

    # ── Detectar la caída ──
    caida_inicio = None
    while True:
        ok = check_health()
        ts = ahora()

        if not ok and caida_inicio is None:
            caida_inicio = time.time()
            print(f"  [{ts}] ✗ CAÍDA DETECTADA — Inicio del conteo RTO")
            print(f"         Corre failover.sh ahora si no lo has hecho.")
            print("-" * 55)
        elif not ok:
            transcurrido = time.time() - caida_inicio
            print(f"  [{ts}] ✗ Sistema caído... {formato_tiempo(transcurrido)}")
        elif ok and caida_inicio is not None:
            # Sistema recuperado
            rto = time.time() - caida_inicio
            print("-" * 55)
            print(f"  [{ts}] ✓ SISTEMA RECUPERADO")
            print()
            print("=" * 55)
            print("   RESULTADO — RTO MEDIDO")
            print("=" * 55)
            print(f"   Caída detectada : {datetime.fromtimestamp(caida_inicio).strftime('%H:%M:%S')}")
            print(f"   Recuperación    : {ts}")
            print(f"   RTO real        : {formato_tiempo(rto)}")
            print()
            if rto < 900:
                print("   ✅ CUMPLE el objetivo (< 15 minutos)")
            else:
                print("   ❌ NO CUMPLE el objetivo (< 15 minutos)")
            print("=" * 55)
            break
        else:
            print(f"  [{ts}] ✓ Sistema OK")

        time.sleep(INTERVALO)


if __name__ == "__main__":
    main()
