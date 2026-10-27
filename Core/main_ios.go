//go:build ios

package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"incy.local/core/engine"
	"unsafe"
)

var vpn engine.Engine

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
