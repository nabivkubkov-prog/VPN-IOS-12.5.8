package engine

import (
	"bytes"
	"context"
	"errors"
	"runtime"
	"runtime/debug"
	"sync"

	_ "github.com/xtls/xray-core/app/dispatcher"
	_ "github.com/xtls/xray-core/app/dns"
	_ "github.com/xtls/xray-core/app/log"
	_ "github.com/xtls/xray-core/app/policy"
	_ "github.com/xtls/xray-core/app/proxyman/inbound"
	_ "github.com/xtls/xray-core/app/proxyman/outbound"
	_ "github.com/xtls/xray-core/app/router"
	"github.com/xtls/xray-core/core"
	_ "github.com/xtls/xray-core/main/json"
	_ "github.com/xtls/xray-core/proxy/dns"
	_ "github.com/xtls/xray-core/proxy/freedom"
	_ "github.com/xtls/xray-core/proxy/http"
	_ "github.com/xtls/xray-core/proxy/shadowsocks"
	_ "github.com/xtls/xray-core/proxy/socks"
	_ "github.com/xtls/xray-core/proxy/trojan"
	_ "github.com/xtls/xray-core/proxy/vless/outbound"
	_ "github.com/xtls/xray-core/proxy/vmess/outbound"
	_ "github.com/xtls/xray-core/transport/internet/grpc"
	_ "github.com/xtls/xray-core/transport/internet/http"
	_ "github.com/xtls/xray-core/transport/internet/reality"
	_ "github.com/xtls/xray-core/transport/internet/tagged/taggedimpl"
	_ "github.com/xtls/xray-core/transport/internet/tcp"
	_ "github.com/xtls/xray-core/transport/internet/tls"
	_ "github.com/xtls/xray-core/transport/internet/udp"
	_ "github.com/xtls/xray-core/transport/internet/websocket"
)

type Engine struct {
	mu         sync.Mutex
	instance   *core.Instance
	runContext context.Context
	cancelRun  context.CancelFunc
}

func init() {
	// A soft Go heap budget; native stacks and TLS buffers are additional memory.
	debug.SetMemoryLimit(16 << 20)
	debug.SetGCPercent(20)
	runtime.GOMAXPROCS(2)
}

func Validate(config []byte) error {
	c, err := core.LoadConfig("json", bytes.NewReader(config))
	if err != nil {
		return err
	}
	instance, err := core.New(c)
	if err != nil {
		return err
	}
	return instance.Close()
}

func (e *Engine) Start(config []byte) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.instance != nil {
		return errors.New("VPN core is already running")
	}
	c, err := core.LoadConfig("json", bytes.NewReader(config))
	if err != nil {
		return err
	}
	instance, err := core.New(c)
	if err != nil {
		return err
	}
	if err = instance.Start(); err != nil {
		_ = instance.Close()
		return err
	}
	e.instance = instance
	e.runContext, e.cancelRun = context.WithCancel(context.Background())
	return nil
}

func (e *Engine) Stop() error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.instance == nil {
		return nil
	}
	e.cancelRun()
	err := e.instance.Close()
	e.instance = nil
	e.runContext = nil
	e.cancelRun = nil
	debug.FreeOSMemory()
	return err
}
