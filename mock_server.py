#!/usr/bin/env python3
"""
GastroCore Online Ordering – Mock Server
- Serves Flutter web build/web/ as static files
- Serves mock API at /api/v1/online/*
- Port 8080 (same origin as Flutter's _resolveApiBaseUrl for localhost)
"""

import json
import os
import mimetypes
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
import re
import uuid

BASE_DIR = Path(__file__).parent / "apps" / "online" / "build" / "web"

DEMO_MENU = {
    "restaurant": {
        "id": "demo",
        "name": "Restaurant GastroCore",
        "description": "Frische Schweizer Küche · Cuisine suisse fraîche",
        "logo_url": None,
        "cover_image_url": None,
        "is_open": True,
        "closed_message": None,
        "estimated_wait_minutes": 20
    },
    "categories": [
        {"id": "cat-1", "name": "Vorspeisen",      "display_order": 1, "color": "#FF9800"},
        {"id": "cat-2", "name": "Hauptgerichte",   "display_order": 2, "color": "#E53935"},
        {"id": "cat-3", "name": "Pizza & Pasta",   "display_order": 3, "color": "#7B1FA2"},
        {"id": "cat-4", "name": "Desserts",        "display_order": 4, "color": "#00897B"},
        {"id": "cat-5", "name": "Getränke",        "display_order": 5, "color": "#1976D2"},
    ],
    "products": [
        # Vorspeisen
        {"id": "p-1",  "category_id": "cat-1", "name": "Gemischter Salat",
         "description": "Frischer Salat mit Saison-Gemüse und Vinaigrette",
         "price": 1450, "tax_group": "standard", "is_available": True, "display_order": 1, "modifier_groups": []},
        {"id": "p-2",  "category_id": "cat-1", "name": "Suppe des Tages",
         "description": "Täglich frisch zubereitet, mit Brot",
         "price": 990,  "tax_group": "standard", "is_available": True, "display_order": 2, "modifier_groups": []},
        {"id": "p-3",  "category_id": "cat-1", "name": "Bruschetta",
         "description": "Röstbrot mit Tomaten, Basilikum und Knoblauch",
         "price": 1190, "tax_group": "standard", "is_available": True, "display_order": 3, "modifier_groups": []},
        # Hauptgerichte
        {"id": "p-4",  "category_id": "cat-2", "name": "Zürcher Geschnetzeltes",
         "description": "Kalbfleisch in Rahmsauce mit Rösti, klassisch zubereitet",
         "price": 3490, "tax_group": "standard", "is_available": True, "display_order": 1, "modifier_groups": []},
        {"id": "p-5",  "category_id": "cat-2", "name": "Poulet Cordon Bleu",
         "description": "Gefüllt mit Schinken und Käse, mit Pommes und Salat",
         "price": 2990, "tax_group": "standard", "is_available": True, "display_order": 2, "modifier_groups": []},
        {"id": "p-6",  "category_id": "cat-2", "name": "Veganes Gemüsecurry",
         "description": "Saisonales Gemüse in Kokosmilch, mit Basmati-Reis",
         "price": 2290, "tax_group": "standard", "is_available": True, "display_order": 3, "modifier_groups": []},
        # Pizza & Pasta
        {"id": "p-7",  "category_id": "cat-3", "name": "Pizza Margherita",
         "description": "Tomatensauce, Mozzarella, Basilikum",
         "price": 1890, "tax_group": "standard", "is_available": True, "display_order": 1,
         "modifier_groups": [{
             "id": "mg-size", "name": "Grösse", "selection_type": "single",
             "min_selections": 1, "max_selections": 1, "is_required": True, "display_order": 1,
             "modifiers": [
                 {"id": "mod-s", "group_id": "mg-size", "name": "Klein",  "price_delta": -200, "is_default": False, "display_order": 1},
                 {"id": "mod-m", "group_id": "mg-size", "name": "Mittel", "price_delta":    0, "is_default": True,  "display_order": 2},
                 {"id": "mod-l", "group_id": "mg-size", "name": "Gross",  "price_delta":  300, "is_default": False, "display_order": 3},
             ]
         }]},
        {"id": "p-8",  "category_id": "cat-3", "name": "Spaghetti Carbonara",
         "description": "Pancetta, Ei, Parmesan, Pfeffer — kein Rahm",
         "price": 2190, "tax_group": "standard", "is_available": True, "display_order": 2, "modifier_groups": []},
        {"id": "p-9",  "category_id": "cat-3", "name": "Penne al Arrabiata",
         "description": "Tomatensauce mit Chili und Knoblauch, vegan",
         "price": 1890, "tax_group": "standard", "is_available": True, "display_order": 3, "modifier_groups": []},
        # Desserts
        {"id": "p-10", "category_id": "cat-4", "name": "Crème Brûlée",
         "description": "Klassische Vanillecreme mit Karamellkruste",
         "price": 950,  "tax_group": "standard", "is_available": True, "display_order": 1, "modifier_groups": []},
        {"id": "p-11", "category_id": "cat-4", "name": "Schokoladenfondue",
         "description": "Dunkle Schweizer Schokolade mit Früchten (für 2)",
         "price": 1890, "tax_group": "standard", "is_available": True, "display_order": 2, "modifier_groups": []},
        # Getränke
        {"id": "p-12", "category_id": "cat-5", "name": "Mineralwasser",
         "description": "Still oder prickelnd, 0.5 l",
         "price": 490,  "tax_group": "standard", "is_available": True, "display_order": 1, "modifier_groups": []},
        {"id": "p-13", "category_id": "cat-5", "name": "Hausgemachte Limonade",
         "description": "Zitrone, Minze und Zucker, 0.4 l",
         "price": 690,  "tax_group": "standard", "is_available": True, "display_order": 2, "modifier_groups": []},
        {"id": "p-14", "category_id": "cat-5", "name": "Kaffee",
         "description": "Espresso, Cappuccino oder Filterkaffee",
         "price": 490,  "tax_group": "standard", "is_available": True, "display_order": 3, "modifier_groups": []},
    ]
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        print(f"  {self.command} {self.path} -> {args[1] if len(args)>1 else ''}")

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Accept")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?")[0]

        # --- Mock API: menu ---
        m = re.match(r"^/api/v1/online/menu/(.+)$", path)
        if m:
            restaurant_id = m.group(1)
            data = dict(DEMO_MENU)
            data["restaurant"] = dict(data["restaurant"], id=restaurant_id)
            self._json(200, data)
            return

        # --- Mock API: order status ---
        m = re.match(r"^/api/v1/online/orders/(.+)/status$", path)
        if m:
            order_id = m.group(1)
            self._json(200, {
                "order_id": order_id,
                "status": "confirmed",
                "estimated_ready_minutes": 20
            })
            return

        # --- Static files ---
        self._serve_static(path)

    def do_POST(self):
        path = self.path.split("?")[0]

        if path == "/api/v1/online/orders":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            try:
                payload = json.loads(body)
            except Exception:
                payload = {}

            order_id = str(uuid.uuid4())[:8].upper()
            self._json(201, {
                "order_id": order_id,
                "order_number": f"#{order_id}",
                "status": "confirmed",
                "estimated_ready_minutes": 20
            })
            return

        self._json(404, {"message": "not found"})

    def _json(self, status, data):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _serve_static(self, url_path):
        # Map URL path to filesystem
        if url_path == "/" or url_path == "":
            file_path = BASE_DIR / "index.html"
        else:
            rel = url_path.lstrip("/")
            file_path = BASE_DIR / rel

        # SPA fallback: if file not found and no extension → index.html
        if not file_path.exists():
            if "." not in file_path.name:
                file_path = BASE_DIR / "index.html"
            else:
                self.send_response(404)
                self.end_headers()
                return

        mime, _ = mimetypes.guess_type(str(file_path))
        if mime is None:
            mime = "application/octet-stream"

        data = file_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    port = 8080
    print(f"GastroCore Online Ordering Mock Server")
    print(f"  Static files : {BASE_DIR}")
    print(f"  Listening on : http://localhost:{port}")
    print(f"  Demo URL     : http://localhost:{port}/demo")
    print(f"  Menu URL     : http://localhost:{port}/demo/menu")
    print()
    server = HTTPServer(("0.0.0.0", port), Handler)
    server.serve_forever()
