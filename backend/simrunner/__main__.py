"""Enables `python -m backend.simrunner`."""

from .lifetime_suite import main

if __name__ == "__main__":
    raise SystemExit(main())
