package manager

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

type Manager struct {
	bundle, data string
	mu           sync.Mutex
	cfg          configuration
	process      *exec.Cmd
	processDone  chan struct{}
	unlock       func()
}

func New(bundle, data string) (*Manager, error) {
	bundle, err := filepath.Abs(bundle)
	if err != nil {
		return nil, err
	}
	data, err = filepath.Abs(data)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(data, 0700); err != nil {
		return nil, err
	}
	unlock, err := lockDataDirectory(data)
	if err != nil {
		return nil, err
	}
	cfg, err := loadConfiguration(data)
	if err != nil {
		unlock()
		return nil, err
	}
	return &Manager{bundle: bundle, data: data, cfg: cfg, unlock: unlock}, nil
}

func (m *Manager) binary(name string) string {
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	return filepath.Join(m.bundle, "bin", name)
}

func mergeEnvironment(overrides []string) []string {
	names := map[string]bool{}
	for _, v := range overrides {
		names[strings.SplitN(v, "=", 2)[0]] = true
	}
	result := []string{}
	for _, v := range os.Environ() {
		if !names[strings.SplitN(v, "=", 2)[0]] {
			result = append(result, v)
		}
	}
	return append(result, overrides...)
}

func (m *Manager) redact(value string) string {
	secrets := []string{m.cfg.DatabaseURL, m.cfg.JWTSecret, m.cfg.PostgresPassword}
	if u, err := url.Parse(m.cfg.DatabaseURL); err == nil && u.User != nil {
		if password, ok := u.User.Password(); ok && password != "" {
			secrets = append(secrets, password)
		}
	}
	for _, secret := range secrets {
		if secret != "" {
			value = strings.ReplaceAll(value, secret, "[已隐藏]")
		}
	}
	return value
}

type cappedBuffer struct{ bytes.Buffer }

func (b *cappedBuffer) Write(p []byte) (int, error) {
	n := len(p)
	if remaining := 1024*1024 - b.Len(); remaining > 0 {
		if len(p) > remaining {
			p = p[:remaining]
		}
		_, _ = b.Buffer.Write(p)
	}
	return n, nil
}

func (m *Manager) run(ctx context.Context, stdin []byte, env []string, name string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = m.bundle
	cmd.Env = mergeEnvironment(env)
	cmd.Stdin = bytes.NewReader(stdin)
	var out cappedBuffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	err := cmd.Run()
	text := m.redact(out.String())
	if err != nil {
		return text, fmt.Errorf("命令执行失败：%s %v\n%s", filepath.Base(name), err, text)
	}
	return text, nil
}

func (m *Manager) prepareDocker() error {
	host, port, _ := net.SplitHostPort(m.cfg.HTTPAddress)
	// JSON quoting is accepted by Compose dotenv and protects paths containing spaces.
	dir := strings.ReplaceAll(m.data, "\\", "/")
	if strings.ContainsAny(dir, "\r\n\"$") {
		return errors.New("Docker 配置目录不能包含换行、双引号或 $ 字符")
	}
	env := fmt.Sprintf("PACTICK_CONFIG_DIR=\"%s\"\nPACTICK_IMAGE=pactick-desktop:%s\nPACTICK_HTTP_PORT=%s\nPACTICK_BIND_ADDRESS=%s\nPOSTGRES_PASSWORD=%s\n", dir, m.cfg.ProjectName, port, host, m.cfg.PostgresPassword)
	if err := writePrivate(filepath.Join(m.data, "api.env"), []byte(m.cfg.apiEnvironment())); err != nil {
		return err
	}
	return writePrivate(filepath.Join(m.data, "docker.env"), []byte(env))
}

func (m *Manager) docker(ctx context.Context, stdin []byte, args ...string) (string, error) {
	if err := m.prepareDocker(); err != nil {
		return "", err
	}
	prefix := []string{"compose", "--project-name", m.cfg.ProjectName, "--project-directory", m.bundle, "--env-file", filepath.Join(m.data, "docker.env"), "-f", filepath.Join(m.bundle, "deploy", "desktop", "compose.yaml")}
	return m.run(ctx, stdin, nil, "docker", append(prefix, args...)...)
}

func (m *Manager) runningNative() bool {
	if m.process == nil {
		return false
	}
	select {
	case <-m.processDone:
		m.process = nil
		return false
	default:
		return true
	}
}

func (m *Manager) startNative() error {
	if m.runningNative() {
		return nil
	}
	logPath := filepath.Join(m.data, "server.log")
	f, err := os.OpenFile(logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	cmd := exec.Command(m.binary("server"))
	cmd.Dir = m.bundle
	cmd.Env = mergeEnvironment(m.cfg.environment(m.cfg.DatabaseURL))
	cmd.Stdout = f
	cmd.Stderr = f
	if err := cmd.Start(); err != nil {
		f.Close()
		return err
	}
	m.process = cmd
	m.processDone = make(chan struct{})
	done := m.processDone
	go func() { _ = cmd.Wait(); _ = f.Close(); close(done) }()
	return nil
}

func (m *Manager) stopNative() error {
	if !m.runningNative() {
		return nil
	}
	if runtime.GOOS == "windows" {
		if err := m.process.Process.Kill(); err != nil {
			return err
		}
	} else {
		if err := m.process.Process.Signal(os.Interrupt); err != nil {
			return err
		}
	}
	select {
	case <-m.processDone:
	case <-time.After(15 * time.Second):
		_ = m.process.Process.Kill()
		<-m.processDone
	}
	m.process = nil
	return nil
}

func (m *Manager) ready() bool {
	_, port, _ := net.SplitHostPort(m.cfg.HTTPAddress)
	client := http.Client{Timeout: 2 * time.Second, Transport: &http.Transport{Proxy: nil}, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	resp, err := client.Get("http://127.0.0.1:" + port + "/readyz")
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode == 200
}

func (m *Manager) waitReady(ctx context.Context) error {
	for i := 0; i < 45; i++ {
		if m.ready() {
			return nil
		}
		if m.cfg.Mode == "native" && !m.runningNative() {
			return errors.New("服务端已退出，请查看运行日志")
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Second):
		}
	}
	return errors.New("服务端未在 45 秒内就绪；请查看日志，服务可能仍在运行")
}

func (m *Manager) Action(ctx context.Context, action string) (string, error) {
	if !m.mu.TryLock() {
		return "", errors.New("另一个管理操作正在执行，请稍后重试")
	}
	defer m.mu.Unlock()
	if m.cfg.Mode == "native" {
		if err := writePrivate(filepath.Join(m.data, "api.env"), []byte(strings.Join(m.cfg.environment(m.cfg.DatabaseURL), "\n")+"\n")); err != nil {
			return "", err
		}
	}
	pending := filepath.Join(m.data, ".migration-pending")
	if _, err := os.Stat(pending); err == nil && (action == "start" || (action == "deploy" && m.cfg.Initialized)) {
		return "", errors.New("上次迁移未完成，请检查备份及日志后重新执行数据库迁移")
	}
	var output strings.Builder
	runDocker := func(args ...string) error {
		out, err := m.docker(ctx, nil, args...)
		output.WriteString(out)
		return err
	}
	if action == "deploy" || action == "migrate" {
		if m.cfg.Mode == "docker" {
			if err := runDocker("build", "api", "migrate", "admin"); err != nil {
				return "", err
			}
			if err := runDocker("up", "-d", "--wait", "--wait-timeout", "90", "postgres"); err != nil {
				return "", err
			}
		}
		if !m.cfg.Initialized || action == "migrate" {
			if m.cfg.Mode == "native" && !m.runningNative() && m.ready() {
				return "", errors.New("监听端口已有其他 API 运行；请先停止外部服务及使用同一数据库的其他写入进程，再执行迁移")
			}
			if m.cfg.Mode == "docker" {
				if err := runDocker("stop", "api"); err != nil {
					return "", err
				}
			} else {
				if err := m.stopNative(); err != nil {
					return "", err
				}
			}
			if err := writePrivate(pending, []byte("migration-started\n")); err != nil {
				return "", err
			}
			if m.cfg.Mode == "docker" {
				if err := runDocker("--profile", "maintenance", "run", "--rm", "--no-deps", "migrate"); err != nil {
					return "", err
				}
			} else {
				out, err := m.run(ctx, nil, m.cfg.environment(m.cfg.DatabaseURL), m.binary("migrate"))
				output.WriteString(out)
				if err != nil {
					return "", err
				}
			}
			m.cfg.Initialized = true
			if err := saveConfiguration(m.data, m.cfg); err != nil {
				return "", err
			}
			if err := os.Remove(pending); err != nil {
				return "", err
			}
		}
		action = "start"
	}
	switch action {
	case "start":
		if !m.cfg.Initialized {
			return "", errors.New("请先执行部署并初始化数据库")
		}
		if m.cfg.Mode == "native" && !m.runningNative() && m.ready() {
			return "", errors.New("监听端口已有其他 API 运行；管理程序不能接管外部服务，请先停止该服务")
		}
		if m.cfg.Mode == "docker" {
			if err := runDocker("up", "-d", "--no-deps", "--wait", "--wait-timeout", "90", "api"); err != nil {
				return "", err
			}
		} else {
			if err := m.startNative(); err != nil {
				return "", err
			}
		}
		if err := m.waitReady(ctx); err != nil {
			return "", err
		}
		output.WriteString("服务端已就绪。公开注册保持关闭。")
	case "stop":
		if m.cfg.Mode == "docker" {
			if err := runDocker("stop", "api"); err != nil {
				return "", err
			}
		} else {
			if err := m.stopNative(); err != nil {
				return "", err
			}
		}
		output.WriteString("API 已停止；数据库和持久化数据保留。")
	case "logs":
		if m.cfg.Mode == "docker" {
			if err := runDocker("logs", "--no-color", "--tail", "100", "api", "postgres"); err != nil {
				return "", err
			}
		} else {
			f, err := os.Open(filepath.Join(m.data, "server.log"))
			if os.IsNotExist(err) {
				return "尚无运行日志", nil
			}
			if err != nil {
				return "", err
			}
			defer f.Close()
			info, err := f.Stat()
			if err != nil {
				return "", err
			}
			if info.Size() > 65536 {
				_, _ = f.Seek(-65536, io.SeekEnd)
			}
			b, err := io.ReadAll(io.LimitReader(f, 65536))
			if err != nil {
				return "", err
			}
			output.WriteString(m.redact(string(b)))
		}
	case "backup":
		return m.backup(ctx)
	default:
		return "", errors.New("未知管理操作")
	}
	return output.String(), nil
}

func (m *Manager) backup(ctx context.Context) (string, error) {
	if m.cfg.Mode != "docker" {
		return "", errors.New("本机模式请使用 PostgreSQL pg_dump 及现有备份流程")
	}
	dir := filepath.Join(m.data, "backups")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return "", err
	}
	suffix, err := randomHex(4)
	if err != nil {
		return "", err
	}
	path := filepath.Join(dir, "pactick-"+time.Now().UTC().Format("20060102-150405")+"-"+suffix+".dump")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return "", err
	}
	if err := m.prepareDocker(); err != nil {
		f.Close()
		os.Remove(path)
		return "", err
	}
	args := []string{"compose", "--project-name", m.cfg.ProjectName, "--project-directory", m.bundle, "--env-file", filepath.Join(m.data, "docker.env"), "-f", filepath.Join(m.bundle, "deploy", "desktop", "compose.yaml"), "exec", "-T", "postgres", "pg_dump", "-U", "pactick", "-d", "pactick", "-Fc"}
	cmd := exec.CommandContext(ctx, "docker", args...)
	cmd.Stdout = f
	var stderr cappedBuffer
	cmd.Stderr = &stderr
	err = cmd.Run()
	closeErr := f.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		os.Remove(path)
		return "", fmt.Errorf("备份失败：%v %s", err, m.redact(stderr.String()))
	}
	backup, err := os.Open(path)
	if err != nil {
		return "", err
	}
	hash := sha256.New()
	_, err = io.Copy(hash, backup)
	backup.Close()
	if err != nil {
		return "", err
	}
	if err := writePrivate(path+".sha256", []byte(hex.EncodeToString(hash.Sum(nil))+"  "+filepath.Base(path)+"\n")); err != nil {
		return "", err
	}
	return "备份已写入 " + path + "，同时生成 SHA-256。请复制到独立介质并验证恢复。", nil
}

func (m *Manager) Close() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	err := m.stopNative()
	if m.unlock != nil {
		m.unlock()
		m.unlock = nil
	}
	return err
}
