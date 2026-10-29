package engine

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestBootstrapChoosesAReachableNumericAddressAndSanitizesFailure(t *testing.T) {
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	address, err := ResolveEndpoint(ctx, "localhost", listener.Addr().(*net.TCPAddr).Port)
	if err != nil || address != "127.0.0.1" {
		t.Fatal("bootstrap did not choose the reachable IPv4 listener", address, err)
	}
	_, err = ResolveEndpoint(ctx, "127.0.0.1", freePort(t))
	if !errors.Is(err, ErrEndpointTCP) || err.Error() != "server TCP connection failed" {
		t.Fatal("unsafe or incorrect dial failure", err)
	}
	_, err = ResolveEndpoint(ctx, "private-credential.invalid", 0)
	if !errors.Is(err, ErrEndpointTCP) || err.Error() != "server TCP connection failed" {
		t.Fatal("invalid endpoint leaked input", err)
	}
}

func startProbeCore(t *testing.T) (*Engine, string) {
	t.Helper()
	port := freePort(t)
	e := &Engine{}
	if err := e.Start(localConfig(port, map[string]any{"protocol": "freedom"})); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = e.Stop() })
	return e, net.JoinHostPort("127.0.0.1", portString(port))
}

func TestProbeUsesSOCKSAndAcceptsEitherResponsiveTarget(t *testing.T) {
	_, socks := startProbeCore(t)
	var requests atomic.Int32
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		w.WriteHeader(http.StatusNoContent)
	}))
	defer origin.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	refused := "http://127.0.0.1:" + portString(freePort(t))
	if result := probeSOCKS(ctx, socks, []string{refused, origin.URL}); result != ProbeSuccess {
		t.Fatal("working target did not pass the probe", result)
	}
	if requests.Load() != 1 {
		t.Fatal("origin was not reached through SOCKS")
	}
	requests.Store(0)
	if result := probeSOCKS(ctx, net.JoinHostPort("127.0.0.1", portString(freePort(t))), []string{origin.URL}); result == ProbeSuccess {
		t.Fatal("probe bypassed a failed SOCKS listener")
	}
	if requests.Load() != 0 {
		t.Fatal("direct fallback reached the origin")
	}
}

func TestProbeDoesNotFollowRedirects(t *testing.T) {
	_, socks := startProbeCore(t)
	var followed atomic.Int32
	destination := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { followed.Add(1) }))
	defer destination.Close()
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, destination.URL, http.StatusFound) }))
	defer origin.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if result := probeSOCKS(ctx, socks, []string{origin.URL}); result != ProbeSuccess {
		t.Fatal("HTTP response was not recognized", result)
	}
	if followed.Load() != 0 {
		t.Fatal("probe followed a redirect")
	}
}

func TestProbeTimesOutAndStopCancelsPendingTraffic(t *testing.T) {
	e, socks := startProbeCore(t)
	started := make(chan struct{}, 2)
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started <- struct{}{}
		<-r.Context().Done()
	}))
	defer origin.Close()
	ctx, cancel := context.WithTimeout(e.runContext, 200*time.Millisecond)
	if result := probeSOCKS(ctx, socks, []string{origin.URL}); result != ProbeTimeout {
		t.Fatal("hanging upstream did not time out", result)
	}
	cancel()
	<-started
	runContext := e.runContext
	result := make(chan ProbeResult, 1)
	go func() { result <- probeSOCKS(runContext, socks, []string{origin.URL}) }()
	select {
	case <-started:
	case <-time.After(3 * time.Second):
		t.Fatal("second probe did not reach the origin")
	}
	if err := e.Stop(); err != nil {
		t.Fatal(err)
	}
	select {
	case value := <-result:
		if value != ProbeCancelled {
			t.Fatal("stop did not cancel the probe", value)
		}
	case <-time.After(time.Second):
		t.Fatal("cancelled probe remained blocked")
	}
	if e.Probe(10808) != ProbeUnavailable {
		t.Fatal("stopped core can still probe")
	}
}
