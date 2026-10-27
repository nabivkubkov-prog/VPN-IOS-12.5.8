// Restores the pinned header symlinks that Git checks out as text on Windows.
package main

import (
	"bytes"
	_ "embed"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

//go:embed vendor-links.json
var manifest []byte

type vendorLink struct {
	Path   string `json:"path"`
	Target string `json:"target"`
}

type linkRepair struct {
	path     string
	target   string
	original []byte
}

func inside(root, path string) bool {
	relative, err := filepath.Rel(root, path)
	return err == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) && !filepath.IsAbs(relative)
}

func inspectLinks(root string, links []vendorLink) ([]linkRepair, error) {
	root, err := filepath.EvalSymlinks(root)
	if err != nil {
		return nil, err
	}
	root, err = filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	var repairs []linkRepair
	for _, link := range links {
		path := filepath.Join(root, filepath.FromSlash(link.Path))
		if !inside(root, path) || filepath.IsAbs(link.Target) {
			return nil, fmt.Errorf("link outside vendor: %s", link.Path)
		}
		parent, err := filepath.EvalSymlinks(filepath.Dir(path))
		if err != nil || !inside(root, parent) {
			return nil, fmt.Errorf("invalid link directory: %s", link.Path)
		}
		path = filepath.Join(parent, filepath.Base(path))
		target, err := filepath.EvalSymlinks(filepath.Join(parent, filepath.FromSlash(link.Target)))
		if err != nil || !inside(root, target) {
			return nil, fmt.Errorf("missing or external link target: %s", link.Path)
		}
		targetInfo, err := os.Stat(target)
		if err != nil || !targetInfo.Mode().IsRegular() {
			return nil, fmt.Errorf("target is not a header: %s", link.Path)
		}
		info, err := os.Lstat(path)
		if os.IsNotExist(err) {
			repairs = append(repairs, linkRepair{path: path, target: link.Target})
			continue
		}
		if err != nil {
			return nil, err
		}
		if info.Mode()&os.ModeSymlink != 0 {
			current, err := os.Readlink(path)
			if err != nil || filepath.ToSlash(current) != link.Target {
				return nil, fmt.Errorf("modified vendor link: %s", link.Path)
			}
			continue
		}
		if !info.Mode().IsRegular() || info.Size() > int64(len(link.Target)+2) {
			return nil, fmt.Errorf("modified vendor header: %s", link.Path)
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		if strings.TrimRight(string(data), "\r\n") != link.Target {
			return nil, fmt.Errorf("modified vendor header: %s", link.Path)
		}
		repairs = append(repairs, linkRepair{path: path, target: link.Target, original: data})
	}
	return repairs, nil
}

func restoreLinks(repairs []linkRepair) error {
	for _, repair := range repairs {
		// Recheck before replacing a placeholder to preserve local edits.
		current, err := os.ReadFile(repair.path)
		if repair.original == nil {
			if !os.IsNotExist(err) {
				return fmt.Errorf("header appeared during restoration: %s", repair.path)
			}
		} else if err != nil || !bytes.Equal(current, repair.original) {
			return fmt.Errorf("header changed during restoration: %s", repair.path)
		}
		temp, err := os.CreateTemp(filepath.Dir(repair.path), ".incy-link-*")
		if err != nil {
			return err
		}
		tempPath := temp.Name()
		if err = temp.Close(); err != nil {
			_ = os.Remove(tempPath)
			return err
		}
		if err = os.Remove(tempPath); err != nil {
			return err
		}
		if err = os.Symlink(repair.target, tempPath); err != nil {
			return err
		}
		// On macOS rename replaces only this checked placeholder, atomically.
		if err = os.Rename(tempPath, repair.path); err != nil {
			_ = os.Remove(tempPath)
			return err
		}
	}
	return nil
}

func run() error {
	check := flag.Bool("check", false, "validate header links without changing files")
	flag.Parse()
	root := "Vendor/hev-socks5-tunnel"
	if flag.NArg() > 0 {
		root = flag.Arg(0)
	}
	var links []vendorLink
	if err := json.Unmarshal(manifest, &links); err != nil {
		return err
	}
	repairs, err := inspectLinks(root, links)
	if err != nil {
		return err
	}
	if *check {
		fmt.Printf("Vendor headers checked: %d links, %d placeholders to restore on macOS.\n", len(links), len(repairs))
		return nil
	}
	if len(repairs) > 0 && runtime.GOOS == "windows" {
		return fmt.Errorf("restore symlinks on macOS before the iOS build; use --check on Windows")
	}
	if err = restoreLinks(repairs); err != nil {
		return err
	}
	fmt.Printf("Vendor headers ready: %d links (%d restored).\n", len(links), len(repairs))
	return nil
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
