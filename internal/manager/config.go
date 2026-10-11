package manager

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

type Settings struct {
	Mode        string `json:"mode"`
	HTTPAddress string `json:"http_address"`
	DatabaseURL string `json:"database_url"`
}

type configuration struct {
	Settings
	JWTSecret        string `json:"jwt_secret"`
	PostgresPassword string `json:"postgres_password"`
	ProjectName      string `json:"project_name"`
	Initialized      bool   `json:"initialized"`
}

func randomHex(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func loadConfiguration(dir string) (configuration, error) {
	path := filepath.Join(dir, "manager.json")
	b, err := os.ReadFile(path)
	if err == nil {
		var cfg configuration
		if err := json.Unmarshal(b, &cfg); err != nil {
			return cfg, errors.New("管理配置不是有效 JSON，请恢复原配置后重试")
		}
		if err := validateSettings(cfg.Settings); err != nil {
			return cfg, err
		}
		if !regexp.MustCompile(`^[a-f0-9]{64}$`).MatchString(cfg.JWTSecret) || !regexp.MustCompile(`^[a-f0-9]{48}$`).MatchString(cfg.PostgresPassword) || !regexp.MustCompile(`^pactick-[a-f0-9]{12}$`).MatchString(cfg.ProjectName) {
			return cfg, errors.New("管理配置缺少密钥或部署标识；请保留数据库和原配置后排查")
		}
		return cfg, nil
	}
	if !os.IsNotExist(err) {
		return configuration{}, err
	}
	jwt, err := randomHex(32)
	if err != nil {
		return configuration{}, err
	}
	password, err := randomHex(24)
	if err != nil {
		return configuration{}, err
	}
	project, err := randomHex(6)
	if err != nil {
		return configuration{}, err
	}
	cfg := configuration{Settings: Settings{Mode: "docker", HTTPAddress: "127.0.0.1:8080"}, JWTSecret: jwt, PostgresPassword: password, ProjectName: "pactick-" + project}
	return cfg, saveConfiguration(dir, cfg)
}

func validateSettings(s Settings) error {
	if strings.ContainsAny(s.DatabaseURL, "\r\n") {
		return errors.New("数据库连接地址不能包含换行")
	}
	if s.Mode != "native" && s.Mode != "docker" {
		return errors.New("请选择 Docker 或本机运行模式")
	}
	host, port, err := net.SplitHostPort(s.HTTPAddress)
	if err != nil || (host != "127.0.0.1" && host != "0.0.0.0") {
		return errors.New("监听地址须为 127.0.0.1:端口 或 0.0.0.0:端口")
	}
	n, err := strconv.Atoi(port)
	if err != nil || n < 1 || n > 65535 {
		return errors.New("端口须在 1–65535 之间")
	}
	if s.Mode == "native" {
		u, err := url.Parse(s.DatabaseURL)
		if err != nil || (u.Scheme != "postgres" && u.Scheme != "postgresql") || u.Host == "" || u.Path == "" {
			return errors.New("本机模式需要 postgres:// 或 postgresql:// 数据库连接地址")
		}
	}
	return nil
}

func saveConfiguration(dir string, cfg configuration) error {
	b, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return writePrivate(filepath.Join(dir, "manager.json"), append(b, '\n'))
}

func writePrivate(path string, b []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".config-*")
	if err != nil {
		return err
	}
	temporary := f.Name()
	defer os.Remove(temporary)
	if err = f.Chmod(0600); err == nil {
		_, err = f.Write(b)
	}
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	return os.Rename(temporary, path)
}

func (c configuration) environment(databaseURL string) []string {
	return []string{"APP_ENV=production", "DATABASE_URL=" + databaseURL, "AUTH_JWT_SECRET=" + c.JWTSecret, "HTTP_ADDRESS=" + c.HTTPAddress, "AUTO_MIGRATE=false", "REGISTRATION_ENABLED=false"}
}

func (c configuration) apiEnvironment() string {
	db := fmt.Sprintf("postgres://pactick:%s@postgres:5432/pactick?sslmode=disable", c.PostgresPassword)
	// Container port remains 8080; only the host port and interface are configurable.
	c.HTTPAddress = ":8080"
	result := ""
	for _, line := range c.environment(db) {
		result += line + "\n"
	}
	return result
}
