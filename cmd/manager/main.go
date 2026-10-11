package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"
	"time"

	"pactick/server/internal/manager"
)

func main() {
	executable, err := os.Executable()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	bundle := flag.String("bundle-dir", filepath.Dir(filepath.Dir(executable)), "发行包目录")
	data := flag.String("data-dir", "", "配置、日志和备份目录；默认发行包内 data")
	noBrowser := flag.Bool("no-browser", false, "仅打印管理网址")
	listen := flag.String("listen", "127.0.0.1:0", "管理界面回环监听地址；0 表示随机端口")
	flag.Parse()
	if *data == "" {
		*data = filepath.Join(*bundle, "data")
	}
	host, _, err := net.SplitHostPort(*listen)
	if err != nil || host != "127.0.0.1" {
		fmt.Fprintln(os.Stderr, "管理界面仅允许监听 127.0.0.1")
		os.Exit(1)
	}
	m, err := manager.New(*bundle, *data)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer m.Close()
	listener, err := net.Listen("tcp", *listen)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	random := make([]byte, 32)
	if _, err := rand.Read(random); err != nil {
		listener.Close()
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	token := hex.EncodeToString(random)
	address := listener.Addr().String()
	url := "http://" + address + "/#" + token
	server := &http.Server{Handler: m.Handler(address, token), ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 60 * time.Second}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	errors := make(chan error, 1)
	go func() { errors <- server.Serve(listener) }()
	fmt.Println("Pactick 服务端管理：", url)
	fmt.Println("关闭管理程序会停止由它启动的本机 API；Docker 服务继续运行。")
	if !*noBrowser {
		var cmd *exec.Cmd
		switch runtime.GOOS {
		case "windows":
			cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
		case "linux":
			cmd = exec.Command("xdg-open", url)
		}
		if cmd != nil {
			if err := cmd.Start(); err != nil {
				fmt.Println("浏览器未能自动打开，请复制上方本机网址。")
			} else {
				go cmd.Wait()
			}
		}
	}
	select {
	case <-ctx.Done():
	case err := <-errors:
		if err != http.ErrServerClosed {
			fmt.Fprintln(os.Stderr, err)
		}
	}
	shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = server.Shutdown(shutdown)
}
