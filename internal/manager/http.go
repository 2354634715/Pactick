package manager

import (
	"context"
	"crypto/subtle"
	"embed"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"pactick/server/internal/admin"
)

//go:embed ui/*
var assets embed.FS

type result struct {
	OK      bool   `json:"ok"`
	Message string `json:"message,omitempty"`
	Data    any    `json:"data,omitempty"`
}

func respond(w http.ResponseWriter, status int, value result) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func decode(w http.ResponseWriter, r *http.Request, v any) error {
	if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		return errors.New("请求需要 application/json")
	}
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16384))
	d.DisallowUnknownFields()
	if err := d.Decode(v); err != nil {
		return errors.New("请求 JSON 无效或字段不受支持")
	}
	if d.Decode(&struct{}{}) != io.EOF {
		return errors.New("请求只能包含一个 JSON 对象")
	}
	return nil
}

func (m *Manager) Handler(host, token string) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			respond(w, 405, result{Message: "使用 GET"})
			return
		}
		if !m.mu.TryLock() {
			respond(w, 200, result{OK: true, Data: map[string]any{"busy": true}})
			return
		}
		defer m.mu.Unlock()
		respond(w, 200, result{OK: true, Data: map[string]any{"busy": false, "mode": m.cfg.Mode, "http_address": m.cfg.HTTPAddress, "database_configured": m.cfg.DatabaseURL != "", "initialized": m.cfg.Initialized, "ready": m.ready(), "data_directory": m.data}})
	})
	mux.HandleFunc("/api/settings", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			respond(w, 405, result{Message: "使用 POST"})
			return
		}
		var input Settings
		if err := decode(w, r, &input); err != nil {
			respond(w, 400, result{Message: err.Error()})
			return
		}
		if !m.mu.TryLock() {
			respond(w, 409, result{Message: "另一个管理操作正在执行"})
			return
		}
		defer m.mu.Unlock()
		if m.runningNative() || m.ready() {
			respond(w, 409, result{Message: "请先停止当前 API，再修改部署配置"})
			return
		}
		if input.DatabaseURL == "" {
			input.DatabaseURL = m.cfg.DatabaseURL
		}
		if err := validateSettings(input); err != nil {
			respond(w, 400, result{Message: err.Error()})
			return
		}
		if m.cfg.Initialized && (input.Mode != m.cfg.Mode || input.DatabaseURL != m.cfg.DatabaseURL) {
			respond(w, 409, result{Message: "已初始化的配置不能更换运行模式或数据库；连接另一实例请使用独立数据目录"})
			return
		}
		candidate := m.cfg
		candidate.Settings = input
		if err := saveConfiguration(m.data, candidate); err != nil {
			respond(w, 500, result{Message: "保存配置失败，请检查目录权限"})
			return
		}
		m.cfg = candidate
		respond(w, 200, result{OK: true, Message: "配置已保存；下次部署或启动时生效。"})
	})
	mux.HandleFunc("/api/action", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			respond(w, 405, result{Message: "使用 POST"})
			return
		}
		var input struct {
			Action string `json:"action"`
		}
		if err := decode(w, r, &input); err != nil {
			respond(w, 400, result{Message: err.Error()})
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Minute)
		defer cancel()
		out, err := m.Action(ctx, input.Action)
		if err != nil {
			respond(w, 400, result{Message: err.Error()})
			return
		}
		respond(w, 200, result{OK: true, Message: out})
	})
	mux.HandleFunc("/api/accounts", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			respond(w, 405, result{Message: "使用 POST"})
			return
		}
		var input admin.CreateAccountRequest
		if err := decode(w, r, &input); err != nil {
			respond(w, 400, result{Message: err.Error()})
			return
		}
		if !m.mu.TryLock() {
			respond(w, 409, result{Message: "另一个管理操作正在执行"})
			return
		}
		defer m.mu.Unlock()
		if !m.cfg.Initialized {
			respond(w, 400, result{Message: "请先完成部署与数据库初始化"})
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), time.Minute)
		defer cancel()
		if m.cfg.Mode == "native" {
			created, err := admin.CreateAccount(ctx, m.cfg.DatabaseURL, input)
			if err != nil {
				var ae *admin.Error
				if errors.As(err, &ae) {
					respond(w, 400, result{Message: ae.Message})
				} else {
					respond(w, 500, result{Message: "创建账户失败，请检查数据库与迁移状态"})
				}
				return
			}
			respond(w, 200, result{OK: true, Data: created, Message: "账户已创建。请使用邮箱和密码在安卓客户端登录。"})
			return
		}
		b, _ := json.Marshal(input)
		out, err := m.docker(ctx, b, "exec", "-T", "api", "/admin", "create-account")
		var reply struct {
			OK       bool   `json:"ok"`
			User     any    `json:"user"`
			Password string `json:"generated_password"`
			Error    struct {
				Message string `json:"message"`
			} `json:"error"`
		}
		if json.Unmarshal([]byte(out), &reply) != nil {
			respond(w, 500, result{Message: "管理命令执行失败，请确认 API 容器已启动且镜像包含 admin 命令"})
			return
		}
		if err != nil || !reply.OK {
			respond(w, 400, result{Message: reply.Error.Message})
			return
		}
		respond(w, 200, result{OK: true, Data: map[string]any{"user": reply.User, "generated_password": reply.Password}, Message: "账户已创建。请保存下方随机密码；关闭此页面后不会再次显示。"})
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method", 405)
			return
		}
		file := "ui/index.html"
		contentType := "text/html; charset=utf-8"
		switch r.URL.Path {
		case "/":
		case "/app.js":
			file = "ui/app.js"
			contentType = "application/javascript; charset=utf-8"
		case "/style.css":
			file = "ui/style.css"
			contentType = "text/css; charset=utf-8"
		default:
			http.NotFound(w, r)
			return
		}
		b, err := assets.ReadFile(file)
		if err != nil {
			http.Error(w, "asset unavailable", 500)
			return
		}
		w.Header().Set("Content-Type", contentType)
		_, _ = w.Write(b)
	})
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; form-action 'self'; base-uri 'none'")
		if r.Host != host {
			http.Error(w, "invalid host", 403)
			return
		}
		if origin := r.Header.Get("Origin"); origin != "" && origin != "http://"+host {
			http.Error(w, "invalid origin", 403)
			return
		}
		if strings.HasPrefix(r.URL.Path, "/api/") && subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Pactick-Manager-Token")), []byte(token)) != 1 {
			respond(w, 401, result{Message: "管理会话已失效，请从管理程序重新打开页面"})
			return
		}
		mux.ServeHTTP(w, r)
	})
}
