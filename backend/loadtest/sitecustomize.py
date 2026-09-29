"""Auto-install the loadtest guard when this directory is on PYTHONPATH.

``python3 -c 'import sitecustomize'`` after ``PYTHONPATH=backend/loadtest``
also works. ``run_server.py`` calls ``guard.install()`` directly so a missed
sitecustomize import cannot start an unguarded Dummy backend.
"""

from guard import install

install()
