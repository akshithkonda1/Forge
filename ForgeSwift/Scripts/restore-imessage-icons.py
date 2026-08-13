#!/usr/bin/env python3
"""Deprecated alias — use make-imessage-icon.py."""
import os
import runpy

runpy.run_path(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "make-imessage-icon.py"),
    run_name="__main__",
)
