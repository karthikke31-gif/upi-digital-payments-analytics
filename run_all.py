"""
UPI Transaction Analytics Project
Script: run_all.py
Purpose: Master runner — executes all analysis scripts in order.
         Run this from the project root directory.

Usage:
    cd upi_analytics
    python run_all.py
"""

import subprocess
import sys
import os
import time

STEPS = [
    ("02_python/00_setup_database.py",    "Database Setup"),
    ("02_python/01_eda_analysis.py",      "EDA Analysis"),
    ("02_python/02_statistical_analysis.py", "Statistical Analysis"),
    ("02_python/03_monte_carlo_whatif.py","Monte Carlo What-If"),
]


def run(script: str, label: str) -> bool:
    print(f"\n{'='*60}")
    print(f"  STEP: {label}")
    print(f"  Script: {script}")
    print("=" * 60)
    t0 = time.time()

    # Run from the 02_python directory (scripts use relative paths)
    script_dir = os.path.dirname(script)
    script_file = os.path.basename(script)

    result = subprocess.run(
        [sys.executable, script_file],
        cwd=script_dir if script_dir else ".",
        capture_output=False,
        text=True,
    )
    elapsed = time.time() - t0

    if result.returncode == 0:
        print(f"  ✓ Completed in {elapsed:.1f}s")
        return True
    else:
        print(f"  ✗ FAILED (returncode={result.returncode})")
        return False


if __name__ == "__main__":
    print("=" * 60)
    print("  UPI Transaction Analytics — Full Pipeline")
    print("=" * 60)

    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    success = 0
    for script, label in STEPS:
        if run(script, label):
            success += 1

    print(f"\n{'='*60}")
    print(f"  Pipeline complete: {success}/{len(STEPS)} steps succeeded")
    print(f"  Outputs in: 02_python/outputs/")
    print("=" * 60)
