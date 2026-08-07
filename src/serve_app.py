"""Serve the crime application locally and open it in the default browser."""

from argparse import ArgumentParser
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Timer
import webbrowser


class AppRequestHandler(SimpleHTTPRequestHandler):
    """Serve the source tree and send the bare server URL to the app."""

    def _redirect_root(self) -> bool:
        if self.path.split("?", 1)[0] != "/":
            return False
        self.send_response(302)
        self.send_header("Location", "/app/")
        self.end_headers()
        return True

    def do_GET(self) -> None:
        if self._redirect_root():
            return
        super().do_GET()

    def do_HEAD(self) -> None:
        if self._redirect_root():
            return
        super().do_HEAD()


def main() -> None:
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()

    source_directory = Path(__file__).resolve().parent
    app_directory = source_directory / "app"
    handler = partial(AppRequestHandler, directory=source_directory)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    url = f"http://localhost:{args.port}/"

    print(f"Serving {app_directory} and its model data at {url}")
    print("Press Ctrl+C to stop the server.")
    Timer(0.4, webbrowser.open_new_tab, args=(url,)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping server.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
