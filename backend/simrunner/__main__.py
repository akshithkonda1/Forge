"""``python -m backend.simrunner`` → ``backend.ai.simrunner``."""
import runpy

runpy.run_module("backend.ai.simrunner", run_name="__main__")
