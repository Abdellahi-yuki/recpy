# recpy

A simple, fast tool for transferring text and files between two devices over a local network. No cloud, no accounts — just a direct TCP connection using an IP address and port.

recpy comes in two types:
- **CLI** (`cli/recpy.py`) — a Python script for desktop/server use (requires Python 3, no external dependencies)
- **Mobile** (`mobile/recpy/`) — a Flutter app for Android

---

## How it works

One device listens on a port, the other connects to it by IP and port. The sender pushes text or files over a custom binary protocol (`RECPY` magic header + command type + payload). Both devices need to be on the same network (or have network access to each other).

**Protocol overview:**

| Command | Type byte | Payload |
|---------|-----------|---------|
| Send text | `0x01` | 4-byte length + UTF-8 text |
| Send file(s) | `0x02` | 4-byte file count, then for each: name length + name + 8-byte file size + raw bytes |

---

## CLI

### Requirements

- Python 3.x (no external dependencies)

### Usage

```
recpy                        # Listen for text and print it (default)
recpy lt                     # Listen for text and print it
recpy lf                     # Listen for files
recpy st "<text>"            # Send text
recpy sf <files...>          # Send files (supports wildcards, e.g. *.mp4)
```


### Options

```
-h	       Print the help message
--ip <ip>      Receiver's IP address (default: 127.0.0.1)
--port <port>  Port number (default: 12345)
```
You can change DEFAULT_IP, the output_dir and DEFAULT_PORT from the script

### Examples

On the receiving device, start listening for text:
```bash
python recpy.py lt --port 5000
```

On the sending device, send some text:
```bash
python recpy.py st "hello from the other device" --ip 192.168.1.42 --port 5000
```

On the receiving device, start listening for files:
```bash
python recpy.py lf --port 5000
```

On the sending device, send a file:
```bash
python recpy.py sf video.mp4 --ip 192.168.1.42 --port 5000


Received files are saved to the work directory. you can change the output_dir from the script. Filename collisions are handled automatically by appending a counter.

---

## Mobile App (Flutter)

The mobile app provides the same send/receive functionality with a GUI.

### Screens

- **Send** — send text or pick files to transfer
- **Receive** — listen on a port; the app accepts incoming text or files
- **Settings** — save default IP/port preferences via `shared_preferences`

### Building

```bash
cd mobile/recpy
flutter pub get
flutter run
```

To build a release APK:
```bash
flutter build apk --release
```

### Dependencies

| Package | Purpose |
|---------|---------|
| `file_picker` | Pick files from device storage |
| `path_provider` | Resolve save paths for received files |
| `shared_preferences` | Persist IP/port settings |

---

## Project Structure

```
recpy/
├── cli/
│   ├── recpy.py              # CLI tool (send/receive text and files)
│   └── recpy_received/       # Default output folder for received files
└── mobile/
    └── recpy/                # Flutter app
        └── lib/
            ├── main.dart
            ├── screens/
            │   ├── send_screen.dart
            │   ├── receive_screen.dart
            │   └── settings_screen.dart
            └── services/
                ├── network_service.dart
                └── storage_service.dart
```

---

## Notes

- Both devices must be reachable over the network (same LAN, hotspot, or VPN)
- The CLI's default IP (`127.0.0.1`) and port (`12345`) can be changed at the top of `recpy.py`
