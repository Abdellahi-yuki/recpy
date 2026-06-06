#!/usr/bin/env python3
import sys
import os
import socket
import struct
import glob

# Default Settings (Can be edited inside the script)
DEFAULT_IP = '127.0.0.1'
DEFAULT_PORT = 12345

USAGE = """recpy - Wireless Text & File Transfer Tool

Usage:
  recpy                  - Listen for text and print it (Default)
  recpy lt               - Listen for text and print it
  recpy lf               - Listen for files
  recpy st "<text>"      - Send text
  recpy sf <files...>    - Send files (supports wildcards like *)

Options:
  --ip <ip>              - Override receiver IP (Default: 127.0.0.1)
  --port <port>          - Override port (Default: 12345)
"""

def print_progress(filename, current, total):
    if total == 0:
        percent = 100.0
    else:
        percent = (current / total) * 100
    bar_length = 30
    filled_length = int(round(bar_length * current / float(total))) if total > 0 else bar_length
    bar = '█' * filled_length + '-' * (bar_length - filled_length)
    sys.stdout.write(f"\r[{bar}] {percent:.1f}% | {filename}")
    sys.stdout.flush()
    if current >= total:
        sys.stdout.write("\n")


def recv_all(conn, n):
    """Receive exactly n bytes from the socket, or return None if EOF is reached."""
    data = bytearray()
    while len(data) < n:
        packet = conn.recv(n - len(data))
        if not packet:
            return None
        data.extend(packet)
    return bytes(data)

def send_text(ip, port, text):
    print(f"Connecting to {ip}:{port} to send text...")
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(10)
            s.connect((ip, port))
            
            # Protocol headers
            magic = b'RECPY'
            cmd_type = b'\x01'
            text_bytes = text.encode('utf-8')
            length = struct.pack('>I', len(text_bytes))
            
            s.sendall(magic + cmd_type + length + text_bytes)
            print("Text sent successfully!")
    except Exception as e:
        print(f"Error sending text: {e}", file=sys.stderr)
        sys.exit(1)

def send_files(ip, port, paths):
    # Expand wildcards and collect actual files
    expanded_files = []
    for path in paths:
        matched = glob.glob(path)
        if not matched:
            # If glob doesn't find anything, try using path directly in case it's a literal path
            if os.path.exists(path):
                expanded_files.append(path)
            else:
                print(f"Warning: File or pattern not found: {path}", file=sys.stderr)
        else:
            for m in matched:
                if os.path.isfile(m):
                    expanded_files.append(m)
                else:
                    print(f"Warning: Skipping directory: {m}", file=sys.stderr)

    if not expanded_files:
        print("Error: No files found to send.", file=sys.stderr)
        sys.exit(1)

    print(f"Found {len(expanded_files)} file(s) to send.")
    print(f"Connecting to {ip}:{port}...")
    
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(15)
            s.connect((ip, port))
            
            magic = b'RECPY'
            cmd_type = b'\x02'
            count = struct.pack('>I', len(expanded_files))
            
            s.sendall(magic + cmd_type + count)
            
            for path in expanded_files:
                filename = os.path.basename(path)
                filename_bytes = filename.encode('utf-8')
                name_len = struct.pack('>I', len(filename_bytes))
                
                file_size = os.path.getsize(path)
                file_len = struct.pack('>Q', file_size) # 8 bytes for file content length
                
                s.sendall(name_len + filename_bytes + file_len)
                
                # Stream file contents
                bytes_sent = 0
                with open(path, 'rb') as f:
                    while bytes_sent < file_size:
                        chunk = f.read(65536) # 64KB chunks
                        if not chunk:
                            break
                        s.sendall(chunk)
                        bytes_sent += len(chunk)
                        print_progress(filename, bytes_sent, file_size)
                        
            print("All files sent successfully!")
    except Exception as e:
        print(f"Error sending files: {e}", file=sys.stderr)
        sys.exit(1)

def listen_text(port):
    print(f"Starting server... Listening for TEXT on port {port}...")
    print("Use Ctrl+C to stop.")
    
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('0.0.0.0', port))
        s.listen(5)
        
        try:
            while True:
                conn, addr = s.accept()
                with conn:
                    # Read magic + command type (6 bytes)
                    header = recv_all(conn, 6)
                    if not header:
                        continue
                    
                    magic = header[:5]
                    cmd_type = header[5]
                    
                    if magic != b'RECPY':
                        print(f"[{addr[0]}] Rejected connection: magic header mismatch.")
                        continue
                    
                    if cmd_type != 1:
                        print(f"[{addr[0]}] Rejected connection: expected text command (1), got {cmd_type}.")
                        continue
                    
                    # Read length (4 bytes)
                    len_bytes = recv_all(conn, 4)
                    if not len_bytes:
                        continue
                    length = struct.unpack('>I', len_bytes)[0]
                    
                    # Read text payload
                    payload_bytes = recv_all(conn, length)
                    if not payload_bytes:
                        print(f"[{addr[0]}] Warning: Connection closed before reading full text.")
                        continue
                    
                    res = payload_bytes.decode('utf-8', errors='replace')
                    print(f"\n[{addr[0]}]: {res}")
        except KeyboardInterrupt:
            print("\nServer stopped.")

def listen_files(port):
    print(f"Starting server... Listening for FILES on port {port}...")
    print("Use Ctrl+C to stop.")
    
    output_dir = '.'
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('0.0.0.0', port))
        s.listen(5)
        
        try:
            while True:
                conn, addr = s.accept()
                with conn:
                    # Read magic + cmd (6 bytes)
                    header = recv_all(conn, 6)
                    if not header:
                        continue
                    
                    magic = header[:5]
                    cmd_type = header[5]
                    
                    if magic != b'RECPY':
                        print(f"[{addr[0]}] Rejected connection: magic header mismatch.")
                        continue
                    
                    if cmd_type != 2:
                        print(f"[{addr[0]}] Rejected: expected file command (2), got {cmd_type}.")
                        continue
                    
                    # Read file count (4 bytes)
                    count_bytes = recv_all(conn, 4)
                    if not count_bytes:
                        continue
                    file_count = struct.unpack('>I', count_bytes)[0]
                    print(f"\nReceiving {file_count} file(s) from {addr[0]}...")
                    
                    for i in range(file_count):
                        # Read name length (4 bytes)
                        name_len_bytes = recv_all(conn, 4)
                        if not name_len_bytes:
                            print("Error reading filename length.")
                            break
                        name_len = struct.unpack('>I', name_len_bytes)[0]
                        
                        # Read name
                        name_bytes = recv_all(conn, name_len)
                        if not name_bytes:
                            print("Error reading filename.")
                            break
                        filename = name_bytes.decode('utf-8', errors='replace')
                        
                        # Read file content length (8 bytes)
                        file_len_bytes = recv_all(conn, 8)
                        if not file_len_bytes:
                            print("Error reading file content length.")
                            break
                        file_size = struct.unpack('>Q', file_len_bytes)[0]
                        
                        # Resolve filename collisions
                        safe_filename = filename
                        counter = 1
                        while os.path.exists(os.path.join(output_dir, safe_filename)):
                            base, ext = os.path.splitext(filename)
                            safe_filename = f"{base}_{counter}{ext}"
                            counter += 1
                            
                        filepath = os.path.join(output_dir, safe_filename)
                        
                        # Receive content and write to file
                        bytes_received = 0
                        with open(filepath, 'wb') as f:
                            while bytes_received < file_size:
                                chunk = conn.recv(min(file_size - bytes_received, 65536))
                                if not chunk:
                                    break
                                f.write(chunk)
                                bytes_received += len(chunk)
                                print_progress(safe_filename, bytes_received, file_size)
                                
                        if bytes_received < file_size:
                            print(f"\nWarning: File transfer incomplete for {safe_filename}.")
                        else:
                            print(f"Saved: {filepath}")
                            
        except KeyboardInterrupt:
            print("\nServer stopped.")

def main():
    args = sys.argv[1:]
    
    # Check for overrides
    target_ip = DEFAULT_IP
    target_port = DEFAULT_PORT
    
    # Simple extraction of optional flags
    cleaned_args = []
    i = 0
    while i < len(args):
        if args[i] == '--ip':
            if i + 1 < len(args):
                target_ip = args[i+1]
                i += 2
            else:
                print("Error: Missing IP address value.", file=sys.stderr)
                sys.exit(1)
        elif args[i] == '--port':
            if i + 1 < len(args):
                try:
                    target_port = int(args[i+1])
                except ValueError:
                    print("Error: Port must be an integer.", file=sys.stderr)
                    sys.exit(1)
                i += 2
            else:
                print("Error: Missing port value.", file=sys.stderr)
                sys.exit(1)
        elif args[i] in ('-h', '--help'):
            print(USAGE)
            sys.exit(0)
        else:
            cleaned_args.append(args[i])
            i += 1

    # Match mode and type
    if not cleaned_args:
        # Default: Listen for text and print it
        listen_text(target_port)
    elif cleaned_args[0] == 'lt':
        listen_text(target_port)
    elif cleaned_args[0] == 'lf':
        listen_files(target_port)
    elif cleaned_args[0] == 'st':
        if len(cleaned_args) < 2:
            print("Error: Missing text payload.", file=sys.stderr)
            sys.exit(1)
        text_payload = " ".join(cleaned_args[1:])
        send_text(target_ip, target_port, text_payload)
    elif cleaned_args[0] == 'sf':
        if len(cleaned_args) < 2:
            print("Error: Missing file paths.", file=sys.stderr)
            sys.exit(1)
        send_files(target_ip, target_port, cleaned_args[1:])
    else:
        print(f"Error: Unknown command '{cleaned_args[0]}'. Expected 'lt', 'lf', 'st', or 'sf'.", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
