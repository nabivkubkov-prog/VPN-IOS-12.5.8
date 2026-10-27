package main

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func linkFixture(t *testing.T) (string, []vendorLink) {
	t.Helper()
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "include"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(root, "src"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "src", "test.h"), []byte("#define TEST 1\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "include", "test.h"), []byte("../src/test.h"), 0644); err != nil {
		t.Fatal(err)
	}
	return root, []vendorLink{{Path: "include/test.h", Target: "../src/test.h"}}
}

func TestCheckAcceptsWindowsPlaceholderWithoutChangingIt(t *testing.T) {
	root, links := linkFixture(t)
	repairs, err := inspectLinks(root, links)
	if err != nil || len(repairs) != 1 {
		t.Fatalf("repairs=%v, error=%v", repairs, err)
	}
	data, err := os.ReadFile(filepath.Join(root, "include", "test.h"))
	if err != nil || string(data) != links[0].Target {
		t.Fatal("check changed the header", err)
	}
}

func TestModifiedHeaderIsPreserved(t *testing.T) {
	root, links := linkFixture(t)
	path := filepath.Join(root, "include", "test.h")
	if err := os.WriteFile(path, []byte("// local header edit\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := inspectLinks(root, links); err == nil {
		t.Fatal("modified header accepted")
	}
	data, _ := os.ReadFile(path)
	if string(data) != "// local header edit\n" {
		t.Fatal("local edit was overwritten")
	}
}

func TestEscapingLinkAndMissingTargetAreRejected(t *testing.T) {
	root, links := linkFixture(t)
	links[0].Path = "../outside.h"
	if _, err := inspectLinks(root, links); err == nil {
		t.Fatal("external source accepted")
	}
	links[0] = vendorLink{Path: "include/test.h", Target: "../../outside.h"}
	if _, err := inspectLinks(root, links); err == nil {
		t.Fatal("external target accepted")
	}
	links[0].Target = "../src/missing.h"
	if _, err := inspectLinks(root, links); err == nil {
		t.Fatal("missing target accepted")
	}
}

func TestAtomicRestoreAndRepeatCheck(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("symlink replacement is performed by the macOS build")
	}
	root, links := linkFixture(t)
	repairs, err := inspectLinks(root, links)
	if err != nil {
		t.Fatal(err)
	}
	if err = restoreLinks(repairs); err != nil {
		t.Fatal(err)
	}
	repairs, err = inspectLinks(root, links)
	if err != nil || len(repairs) != 0 {
		t.Fatal("restoration is not idempotent", err)
	}
	data, err := os.ReadFile(filepath.Join(root, "include", "test.h"))
	if err != nil || string(data) != "#define TEST 1\n" {
		t.Fatal("wrong header target", err)
	}
}

func TestEditAfterInspectionIsPreserved(t *testing.T) {
	root, links := linkFixture(t)
	repairs, err := inspectLinks(root, links)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, "include", "test.h")
	if err = os.WriteFile(path, []byte("changed"), 0644); err != nil {
		t.Fatal(err)
	}
	if err = restoreLinks(repairs); err == nil {
		t.Fatal("concurrent edit accepted")
	}
	data, _ := os.ReadFile(path)
	if string(data) != "changed" {
		t.Fatal("concurrent edit was overwritten")
	}
}
