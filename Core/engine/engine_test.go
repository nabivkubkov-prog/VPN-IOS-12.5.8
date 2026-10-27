package engine

import (
	"encoding/binary"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"golang.org/x/net/proxy"
)

func TestProtocolFixtures(t *testing.T) {
	files, err := filepath.Glob("testdata/*.json")
	if err != nil || len(files) < 6 {
		t.Fatal("Missing protocol fixtures", err)
	}
	if directory := os.Getenv("INCY_CONFIG_INPUT"); directory != "" {
		swiftFiles, err := filepath.Glob(filepath.Join(directory, "*.json"))
		if err != nil || len(swiftFiles) != 7 { t.Fatal("Missing Swift-generated fixtures", err) }
		files = append(files, swiftFiles...)
	}
	for _, file := range files {
		t.Run(filepath.Base(file), func(t *testing.T) {
			config, err := os.ReadFile(file)
			if err != nil {
				t.Fatal(err)
			}
			if err = Validate(config); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestMalformedConfigDoesNotStart(t *testing.T) {
	var e Engine
	if err := e.Start([]byte(`{"outbounds":[{"protocol":"not-a-protocol"}]}`)); err == nil {
		t.Fatal("unsupported protocol accepted")
	}
	if err := e.Start([]byte(`not-json`)); err == nil {
		t.Fatal("malformed JSON accepted")
	}
	if err := e.Stop(); err != nil {
		t.Fatal(err)
	}
}

func freePort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

func localConfig(port int, outbound map[string]any) []byte {
	j := map[string]any{
		"log":       map[string]any{"loglevel": "none"},
		"inbounds":  []any{map[string]any{"listen": "127.0.0.1", "port": port, "protocol": "socks", "settings": map[string]any{"auth": "noauth", "udp": true, "ip": "127.0.0.1"}}},
		"outbounds": []any{outbound},
	}
	bytes, _ := json.Marshal(j)
	return bytes
}

func TestSOCKSOverHTTPConnectAndRestart(t *testing.T) {
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte("incy-local-origin")) }))
	defer origin.Close()
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "CONNECT" {
			http.Error(w, "CONNECT required", 405)
			return
		}
		destination, err := net.DialTimeout("tcp", r.Host, 3*time.Second)
		if err != nil {
			http.Error(w, "dial failed", 502)
			return
		}
		client, buffer, err := w.(http.Hijacker).Hijack()
		if err != nil {
			_ = destination.Close()
			return
		}
		_, _ = buffer.WriteString("HTTP/1.1 200 Connection Established\r\n\r\n")
		_ = buffer.Flush()
		go func() { _, _ = io.Copy(destination, client); _ = destination.Close() }()
		_, _ = io.Copy(client, destination)
		_ = client.Close()
	}))
	defer upstream.Close()
	upstreamAddress := upstream.Listener.Addr().(*net.TCPAddr)
	port := freePort(t)
	config := localConfig(port, map[string]any{"protocol": "http", "settings": map[string]any{"servers": []any{map[string]any{"address": "127.0.0.1", "port": upstreamAddress.Port}}}})
	var e Engine
	defer e.Stop()
	for cycle := 0; cycle < 3; cycle++ {
		if err := e.Start(config); err != nil {
			t.Fatal(err)
		}
		if err := e.Start(config); err == nil {
			t.Fatal("double start accepted")
		}
		dialer, err := proxy.SOCKS5("tcp", net.JoinHostPort("127.0.0.1", portString(port)), nil, &net.Dialer{Timeout: 3 * time.Second})
		if err != nil {
			t.Fatal(err)
		}
		transport := &http.Transport{Dial: dialer.Dial, DisableKeepAlives: true}
		client := &http.Client{Transport: transport, Timeout: 5 * time.Second}
		response, err := client.Get(origin.URL)
		if err != nil {
			t.Fatal(err)
		}
		body, err := io.ReadAll(response.Body)
		_ = response.Body.Close()
		transport.CloseIdleConnections()
		if err != nil || string(body) != "incy-local-origin" {
			t.Fatal("unexpected response", string(body), err)
		}
		if err = e.Stop(); err != nil {
			t.Fatal(err)
		}
		if err = e.Stop(); err != nil {
			t.Fatal("stop must be idempotent", err)
		}
	}
}

func portString(port int) string {
	address := &net.TCPAddr{Port: port}
	_, value, _ := net.SplitHostPort(address.String())
	return value
}

func TestSOCKSUDPRelay(t *testing.T) {
	echo, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer echo.Close()
	go func() {
		b := make([]byte, 2048)
		n, a, err := echo.ReadFromUDP(b)
		if err == nil {
			_, _ = echo.WriteToUDP(b[:n], a)
		}
	}()
	port := freePort(t)
	var e Engine
	if err = e.Start(localConfig(port, map[string]any{"protocol": "freedom"})); err != nil {
		t.Fatal(err)
	}
	defer e.Stop()
	control, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", portString(port)), 3*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer control.Close()
	_ = control.SetDeadline(time.Now().Add(5 * time.Second))
	_, _ = control.Write([]byte{5, 1, 0})
	greeting := make([]byte, 2)
	if _, err = io.ReadFull(control, greeting); err != nil || greeting[1] != 0 {
		t.Fatal("SOCKS handshake", err)
	}
	_, _ = control.Write([]byte{5, 3, 0, 1, 0, 0, 0, 0, 0, 0})
	reply := make([]byte, 10)
	if _, err = io.ReadFull(control, reply); err != nil || reply[1] != 0 || reply[3] != 1 {
		t.Fatal("UDP associate", err, reply)
	}
	relay := &net.UDPAddr{IP: net.IP(reply[4:8]), Port: int(binary.BigEndian.Uint16(reply[8:10]))}
	udp, err := net.DialUDP("udp4", nil, relay)
	if err != nil {
		t.Fatal(err)
	}
	defer udp.Close()
	_ = udp.SetDeadline(time.Now().Add(5 * time.Second))
	payload := []byte{0, 0, 0, 1, 127, 0, 0, 1, 0, 0}
	binary.BigEndian.PutUint16(payload[8:10], uint16(echo.LocalAddr().(*net.UDPAddr).Port))
	payload = append(payload, []byte("incy-udp")...)
	if _, err = udp.Write(payload); err != nil {
		t.Fatal(err)
	}
	answer := make([]byte, 2048)
	n, err := udp.Read(answer)
	if err != nil || n < 10 || string(answer[10:n]) != "incy-udp" {
		t.Fatal("UDP relay response", err, n)
	}
}
