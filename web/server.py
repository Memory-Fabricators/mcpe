#!/usr/bin/env python3
"""Serve the Emscripten pthread build with required isolation headers."""

import argparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class IsolatedHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        super().end_headers()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", default="build-web/handheld")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()

    directory = Path(args.directory).resolve()

    def handler(*a, **kw):
        return IsolatedHandler(*a, directory=directory, **kw)

    server = ThreadingHTTPServer(("", args.port), handler)
    print(f"Serving {directory} at http://localhost:{args.port}/")
    server.serve_forever()


if __name__ == "__main__":
    main()
