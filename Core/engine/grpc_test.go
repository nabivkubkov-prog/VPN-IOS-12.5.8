package engine

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/xtls/xray-core/core"
	_ "github.com/xtls/xray-core/proxy/vless/inbound"
	"golang.org/x/net/proxy"
)

func TestVLESSOverGRPCGunAndMulti(t *testing.T) {
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("incy-grpc-origin"))
	}))
	defer origin.Close()
	for _, mode := range []string{"gun", "multi"} {
		t.Run(mode, func(t *testing.T) {
			multi := mode == "multi"
			serverPort := freePort(t)
			const uuid = "11111111-1111-4111-8111-111111111111"
			grpcSettings := map[string]any{"serviceName": "legacy-vpn", "multiMode": multi}
			serverConfig, err := json.Marshal(map[string]any{
				"log": map[string]any{"loglevel": "none"},
				"inbounds": []any{map[string]any{
					"listen": "127.0.0.1", "port": serverPort, "protocol": "vless",
					"settings":       map[string]any{"decryption": "none", "clients": []any{map[string]any{"id": uuid}}},
					"streamSettings": map[string]any{"network": "grpc", "security": "none", "grpcSettings": grpcSettings},
				}},
				"outbounds": []any{map[string]any{"protocol": "freedom"}},
			})
			if err != nil {
				t.Fatal(err)
			}
			server, err := core.StartInstance("json", serverConfig)
			if err != nil {
				t.Fatal(err)
			}
			defer server.Close()
			clientGRPC := map[string]any{"serviceName": "legacy-vpn", "multiMode": multi, "authority": "grpc.example.invalid"}
			clientPort := freePort(t)
			config := localConfig(clientPort, map[string]any{
				"protocol": "vless",
				"settings": map[string]any{"vnext": []any{map[string]any{
					"address": "127.0.0.1", "port": serverPort,
					"users": []any{map[string]any{"id": uuid, "encryption": "none"}},
				}}},
				"streamSettings": map[string]any{"network": "grpc", "security": "none", "grpcSettings": clientGRPC},
			})
			var clientEngine Engine
			if err = clientEngine.Start(config); err != nil {
				t.Fatal(err)
			}
			defer clientEngine.Stop()
			probeContext, cancelProbe := context.WithTimeout(context.Background(), 5*time.Second)
			probeResult := probeSOCKS(probeContext, net.JoinHostPort("127.0.0.1", portString(clientPort)), []string{origin.URL})
			cancelProbe()
			if probeResult != ProbeSuccess {
				t.Fatal("gRPC upstream probe failed", probeResult)
			}
			dialer, err := proxy.SOCKS5("tcp", net.JoinHostPort("127.0.0.1", portString(clientPort)), nil, &net.Dialer{Timeout: 3 * time.Second})
			if err != nil {
				t.Fatal(err)
			}
			transport := &http.Transport{Dial: dialer.Dial, DisableKeepAlives: true}
			defer transport.CloseIdleConnections()
			client := &http.Client{Transport: transport, Timeout: 5 * time.Second}
			response, err := client.Get(origin.URL)
			if err != nil {
				t.Fatal(err)
			}
			body, err := io.ReadAll(response.Body)
			_ = response.Body.Close()
			if err != nil || string(body) != "incy-grpc-origin" {
				t.Fatal("gRPC round trip failed", err)
			}
		})
	}
}
