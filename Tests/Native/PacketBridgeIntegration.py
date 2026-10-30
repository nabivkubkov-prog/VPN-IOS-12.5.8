"""Exercise production packet framing and real Apple HEV TCP/UDP, without a VPN or credentials."""
import ctypes as C
import ipaddress
import os
import select
import socket
import socketserver
import struct
import sys
import threading
import time

BODY = b"incy-native-response-" * 400
RESPONSE = b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(BODY)).encode() + b"\r\nConnection: close\r\n\r\n" + BODY


def read_exact(stream, count):
    data = bytearray()
    while len(data) < count:
        chunk = stream.recv(count - len(data))
        if not chunk:
            raise EOFError("SOCKS stream closed")
        data.extend(chunk)
    return bytes(data)


class SocksHandler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(5)
        try:
            version, methods = read_exact(self.request, 2)
            assert version == 5 and 0 in read_exact(self.request, methods)
            self.request.sendall(b"\x05\x00")
            version, command, reserved, kind = read_exact(self.request, 4)
            assert version == 5 and reserved == 0
            if kind == 1:
                read_exact(self.request, 6)
            elif kind == 4:
                read_exact(self.request, 18)
            else:
                raise AssertionError("Expected numeric SOCKS target")
            port = self.server.udp.getsockname()[1] if command == 3 else 0
            address = ipaddress.ip_address(self.server.server_address[0])
            kind = 1 if address.version == 4 else 4
            self.request.sendall(bytes([5, 0, 0, kind]) + address.packed + struct.pack("!H", port))
            if command == 3:
                while self.request.recv(1):
                    pass
            else:
                assert command == 1
                request = bytearray()
                while b"\r\n\r\n" not in request:
                    request.extend(read_exact(self.request, 1))
                assert request.startswith(b"GET /")
                self.request.sendall(RESPONSE)
        except (EOFError, ConnectionError, TimeoutError):
            pass


class SocksServer(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address):
        self.address_family = socket.AF_INET6 if ":" in address else socket.AF_INET
        super().__init__((address, 0), SocksHandler)
        self.udp = socket.socket(self.address_family, socket.SOCK_DGRAM)
        self.udp.bind((address, 0))
        self.udp.settimeout(0.2)
        self.finished = threading.Event()
        self.echo = threading.Thread(target=self.echo_udp, daemon=True)
        self.echo.start()
        self.thread = threading.Thread(target=self.serve_forever, daemon=True)
        self.thread.start()

    def echo_udp(self):
        while not self.finished.is_set():
            try:
                data, peer = self.udp.recvfrom(65535)
                self.udp.sendto(data, peer)
            except TimeoutError:
                pass

    def close(self):
        self.finished.set()
        self.shutdown()
        self.thread.join(2)
        self.echo.join(2)
        self.udp.close()
        self.server_close()


def checksum(data):
    if len(data) % 2:
        data += b"\x00"
    value = sum(struct.unpack("!" + "H" * (len(data) // 2), data))
    while value >> 16:
        value = (value & 65535) + (value >> 16)
    return (~value) & 65535


def addresses(version):
    return (ipaddress.ip_address(value).packed for value in
            (("198.18.0.2", "203.0.113.20") if version == 4 else ("fd00:1::2", "2001:db8::20")))


def packet(version, protocol, payload):
    source, destination = addresses(version)
    if version == 4:
        header = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(payload), 1, 0, 64, protocol, 0, source, destination)
        return header[:10] + struct.pack("!H", checksum(header)) + header[12:] + payload
    return struct.pack("!IHBB16s16s", 6 << 28, len(payload), protocol, 64, source, destination) + payload


def pseudo(version, protocol, length):
    source, destination = addresses(version)
    tail = struct.pack("!BBH", 0, protocol, length) if version == 4 else struct.pack("!I3xB", length, protocol)
    return source + destination + tail


def tcp_packet(version, sequence, acknowledgement, flags, data=b"", options=b""):
    header = struct.pack("!HHIIBBHHH", 42000 + version, 80, sequence, acknowledgement,
                         (5 + len(options) // 4) << 4, flags, 65535, 0, 0) + options
    value = checksum(pseudo(version, 6, len(header) + len(data)) + header + data)
    return packet(version, 6, header[:16] + struct.pack("!H", value) + header[18:] + data)


class Tunnel:
    READY = C.CFUNCTYPE(None, C.c_void_p)

    def __init__(self, library, address, port):
        self.library = library
        self.fds = (C.c_int * 2)(-1, -1)
        assert library.incy_socket_pair(self.fds) == 0
        assert library.incy_tunnel_prepare() == 0
        self.ready = threading.Event()
        self.callback = self.READY(lambda context: self.ready.set())
        config = f"""tunnel:
  mtu: 1280
  ipv4: 198.18.0.1
  ipv6: 'fd00:1::1'
socks5:
  address: '{address}'
  port: {port}
  udp: 'udp'
misc:
  task-stack-size: 24576
  tcp-buffer-size: 4096
  udp-recv-buffer-size: 32768
  udp-copy-buffer-nums: 2
  max-session-count: 48
  connect-timeout: 1000
  tcp-read-write-timeout: 5000
  udp-read-write-timeout: 5000
  log-file: null
  log-level: error
""".encode()
        self.config = C.create_string_buffer(config)
        self.result = None
        def run():
            self.result = library.incy_tunnel_run(self.config, len(config), self.fds[1], self.callback, None)
        self.thread = threading.Thread(target=run, daemon=True)
        self.thread.start()
        assert self.ready.wait(3), "Real HEV did not initialize"

    def send(self, version, data):
        memory = C.create_string_buffer(data)
        family = socket.AF_INET if version == 4 else socket.AF_INET6
        assert self.library.incy_send_packet(self.fds[0], memory, len(data), family) == 0

    def receive(self, version, protocol, deadline):
        while time.monotonic() < deadline:
            if not select.select([self.fds[0]], [], [], max(0, deadline - time.monotonic()))[0]:
                break
            memory = C.create_string_buffer(65536)
            family = C.c_int()
            count = self.library.incy_receive_packet(self.fds[0], memory, len(memory), C.byref(family))
            if count <= 0:
                continue
            data = memory.raw[:count]
            if data[0] >> 4 != version:
                continue
            assert family.value == (socket.AF_INET if version == 4 else socket.AF_INET6), "Address-family framing mismatch"
            offset = (data[0] & 15) * 4 if version == 4 else 40
            if data[9 if version == 4 else 6] == protocol:
                return data, data[offset:]
        raise AssertionError(f"Real HEV returned no IPv{version} protocol {protocol} packet")

    def udp(self, version):
        payload = b"incy-dns-udp-roundtrip"
        header = struct.pack("!HHHH", 53000 + version, 53, 8 + len(payload), 0)
        value = checksum(pseudo(version, 17, len(header) + len(payload)) + header + payload) or 65535
        self.send(version, packet(version, 17, header[:6] + struct.pack("!H", value) + payload))
        _, response = self.receive(version, 17, time.monotonic() + 3)
        assert struct.unpack("!HH", response[:4]) == (53, 53000 + version)
        assert response[8:] == payload, "UDP content did not survive SOCKS and packet framing"

    def tcp(self, version):
        client_sequence = 1001
        mss = 1280 - (40 if version == 4 else 60)
        self.send(version, tcp_packet(version, 1000, 0, 2, options=struct.pack("!BBH", 2, 4, mss)))
        _, syn = self.receive(version, 6, time.monotonic() + 3)
        assert syn[13] & 0x12 == 0x12, "Expected SYN/ACK"
        server_sequence = struct.unpack("!I", syn[4:8])[0] + 1
        self.send(version, tcp_packet(version, client_sequence, server_sequence, 16))
        request = b"GET / HTTP/1.1\r\nHost: example.invalid\r\nConnection: close\r\n\r\n"
        self.send(version, tcp_packet(version, client_sequence, server_sequence, 24, request))
        client_sequence += len(request)
        response = bytearray()
        deadline = time.monotonic() + 4
        while len(response) < len(RESPONSE):
            raw, segment = self.receive(version, 6, deadline)
            assert not segment[13] & 4, "HEV reset TCP before returning HTTP content"
            offset = (segment[12] >> 4) * 4
            content = segment[offset:]
            if not content:
                continue
            sequence = struct.unpack("!I", segment[4:8])[0]
            assert len(raw) <= 1280, "HEV returned a packet exceeding the negotiated MTU"
            if sequence == server_sequence:
                response.extend(content)
                server_sequence += len(content)
            else:
                assert sequence < server_sequence, "TCP response had a gap"
            self.send(version, tcp_packet(version, client_sequence, server_sequence, 16))
        assert bytes(response) == RESPONSE, "HTTP content did not survive real HEV TCP"

    def close(self):
        self.library.incy_tunnel_stop()
        self.thread.join(3)
        assert not self.thread.is_alive(), "Real HEV shutdown remained blocked"
        assert self.result == 0, f"Real HEV returned {self.result}"
        for fd in self.fds:
            os.close(fd)


def main():
    library = C.CDLL(sys.argv[1])
    library.incy_tunnel_run.argtypes = [C.c_void_p, C.c_uint, C.c_int, Tunnel.READY, C.c_void_p]
    library.incy_socket_pair.argtypes = [C.POINTER(C.c_int)]
    library.incy_send_packet.argtypes = [C.c_int, C.c_void_p, C.c_size_t, C.c_int]
    library.incy_receive_packet.argtypes = [C.c_int, C.c_void_p, C.c_size_t, C.POINTER(C.c_int)]
    library.incy_hev_failure_stage.restype = C.c_char_p
    for address in ["::1", "127.0.0.1"]:
        server = SocksServer(address)
        try:
            for cycle in range(2):
                tunnel = Tunnel(library, address, server.server_address[1])
                try:
                    for version in [4, 6]:
                        tunnel.udp(version)
                        tunnel.tcp(version)
                except Exception as error:
                    stage = library.incy_hev_failure_stage().decode()
                    code = library.incy_hev_failure_errno()
                    raise AssertionError(f"{error}; native stage={stage} errno={code}") from error
                finally:
                    tunnel.close()
                print(f"Real Apple HEV via {address}, IPv4/IPv6 TCP, UDP, MTU and restart: cycle {cycle + 1} passed", flush=True)
        finally:
            server.close()


if __name__ == "__main__":
    main()
