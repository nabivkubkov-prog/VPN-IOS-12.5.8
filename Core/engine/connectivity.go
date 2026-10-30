package engine

import (
	"context"
	"errors"
	"net"
	"net/http"
	"strconv"
	"time"

	"golang.org/x/net/proxy"
)

var (
	ErrEndpointDNS = errors.New("server name resolution failed")
	ErrEndpointTCP = errors.New("server TCP connection failed")
)

// ResolveEndpoint runs before VPN routes are installed. Dialer's DNS ordering
// and Happy Eyeballs choose an address that this network can actually reach.
// Neither the raw dial error nor the hostname leaves this function on failure.
func ResolveEndpoint(ctx context.Context, host string, port int) (string, error) {
	if host == "" || port < 1 || port > 65535 {
		return "", ErrEndpointTCP
	}
	connection, err := (&net.Dialer{}).DialContext(ctx, "tcp", net.JoinHostPort(host, strconv.Itoa(port)))
	if err != nil {
		var dnsError *net.DNSError
		if errors.As(err, &dnsError) {
			return "", ErrEndpointDNS
		}
		return "", ErrEndpointTCP
	}
	defer connection.Close()
	address, ok := connection.RemoteAddr().(*net.TCPAddr)
	if !ok || address.IP == nil {
		return "", ErrEndpointTCP
	}
	return address.IP.String(), nil
}

type ProbeResult int

const (
	ProbeSuccess ProbeResult = iota
	ProbeUnavailable
	ProbeTimeout
	ProbeNoResponse
	ProbeCancelled
)

// Both requests use SOCKS, including remote DNS for the hostname target. A
// response from either proves a real round trip, independently of VPN status.
// Redirects are not followed and no response content is retained or logged.
var connectivityTargets = []string{
	"http://1.1.1.1/cdn-cgi/trace",
	"http://connectivitycheck.gstatic.com/generate_204",
}

func (e *Engine) Probe(port int) ProbeResult {
	e.mu.Lock()
	runContext := e.runContext
	running := e.instance != nil
	e.mu.Unlock()
	if !running || runContext == nil || port < 1 || port > 65535 {
		return ProbeUnavailable
	}
	ctx, cancel := context.WithTimeout(runContext, 10*time.Second)
	defer cancel()
	// Match HEV's native IPv6 loopback connection on iOS 12.
	return probeSOCKS(ctx, net.JoinHostPort("::1", strconv.Itoa(port)), connectivityTargets)
}

func probeSOCKS(ctx context.Context, address string, targets []string) ProbeResult {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	responses := make(chan bool, len(targets))
	for _, target := range targets {
		go func(target string) {
			dialer, err := proxy.SOCKS5("tcp", address, nil, &net.Dialer{})
			if err != nil {
				responses <- false
				return
			}
			contextDialer, ok := dialer.(proxy.ContextDialer)
			if !ok {
				responses <- false
				return
			}
			transport := &http.Transport{
				DialContext:           contextDialer.DialContext,
				DisableKeepAlives:     true,
				ResponseHeaderTimeout: 8 * time.Second,
			}
			defer transport.CloseIdleConnections()
			client := &http.Client{
				Transport:     transport,
				CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
			}
			request, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
			if err != nil {
				responses <- false
				return
			}
			request.Header.Set("User-Agent", "INCY-iOS12/1.0")
			response, err := client.Do(request)
			if err != nil {
				responses <- false
				return
			}
			_ = response.Body.Close()
			responses <- true
		}(target)
	}
	for range targets {
		select {
		case success := <-responses:
			if success {
				return ProbeSuccess
			}
		case <-ctx.Done():
			if errors.Is(ctx.Err(), context.DeadlineExceeded) {
				return ProbeTimeout
			}
			return ProbeCancelled
		}
	}
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return ProbeTimeout
	}
	if ctx.Err() != nil {
		return ProbeCancelled
	}
	return ProbeNoResponse
}
