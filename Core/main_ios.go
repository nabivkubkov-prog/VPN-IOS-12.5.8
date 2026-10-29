//go:build ios

package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"context"
	"errors"
	"incy.local/core/engine"
	"time"
	"unsafe"
)

var vpn engine.Engine

//export IncyXrayResolve
func IncyXrayResolve(host *C.char, port C.int) *C.char {
	if host == nil {
		return C.CString("TCP_FAILED")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	address, err := engine.ResolveEndpoint(ctx, C.GoString(host), int(port))
	if errors.Is(err, engine.ErrEndpointDNS) {
		return C.CString("DNS_FAILED")
	}
	if err != nil {
		return C.CString("TCP_FAILED")
	}
	return C.CString(address)
}

//export IncyXrayProbe
func IncyXrayProbe(port C.int) C.int { return C.int(vpn.Probe(int(port))) }

//export IncyXrayStart
func IncyXrayStart(config *C.char) *C.char {
	if config == nil {
		return C.CString("Missing configuration")
	}
	if err := vpn.Start([]byte(C.GoString(config))); err != nil {
		return C.CString(err.Error())
	}
	return nil
}

//export IncyXrayStop
func IncyXrayStop() { _ = vpn.Stop() }

//export IncyXrayFree
func IncyXrayFree(value *C.char) { C.free(unsafe.Pointer(value)) }

func main() {}
