//go:build !windows

package manager

import (
	"errors"
	"golang.org/x/sys/unix"
	"os"
	"path/filepath"
)

func lockDataDirectory(data string) (func(), error) {
	f, err := os.OpenFile(filepath.Join(data, "manager.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, err
	}
	if err := unix.Flock(int(f.Fd()), unix.LOCK_EX|unix.LOCK_NB); err != nil {
		f.Close()
		return nil, errors.New("该数据目录已被其他管理程序使用，或无法取得目录锁")
	}
	return func() { _ = unix.Flock(int(f.Fd()), unix.LOCK_UN); f.Close() }, nil
}
