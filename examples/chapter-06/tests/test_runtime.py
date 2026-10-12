import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time
import unittest
import urllib.error
import urllib.request

class RuntimeContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            cls.port = sock.getsockname()[1]
        app = Path(__file__).resolve().parents[1] / 'app.py'
        cls.process = subprocess.Popen([sys.executable, str(app)],
            env={**os.environ, 'PORT': str(cls.port)},
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        cls.base = f'http://127.0.0.1:{cls.port}'
        for _ in range(50):
            try:
                urllib.request.urlopen(cls.base + '/readyz', timeout=1).close()
                return
            except (OSError, urllib.error.URLError):
                time.sleep(.1)
        cls.process.kill()
        raise RuntimeError('Application failed to become ready')

    @classmethod
    def tearDownClass(cls):
        cls.process.send_signal(signal.SIGTERM)
        try:
            cls.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            cls.process.kill()
            raise AssertionError('Application failed graceful termination')
        if cls.process.returncode != 0:
            raise AssertionError('Application exited unsuccessfully')

    def test_ready_payload(self):
        with urllib.request.urlopen(self.base + '/readyz', timeout=2) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(json.load(response)['service'], 'orders-api')

    def test_unknown_path_rejected(self):
        with self.assertRaises(urllib.error.HTTPError) as caught:
            urllib.request.urlopen(self.base + '/unknown', timeout=2)
        self.assertEqual(caught.exception.code, 404)
