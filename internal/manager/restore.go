package manager

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"pactick/server/internal/database"
)

var backupNamePattern = regexp.MustCompile(`^pactick-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}\.dump$`)

// libpq reads credentials from the child environment, never command arguments.
func postgresEnvironment(databaseURL, overrideDatabase string) ([]string, error) {
	u, err := url.Parse(databaseURL)
	if err != nil || (u.Scheme != "postgres" && u.Scheme != "postgresql") || u.Host == "" {
		return nil, errors.New("PostgreSQL 连接地址无效")
	}
	query := u.Query()
	password := query.Get("password")
	if u.User != nil {
		if value, ok := u.User.Password(); ok {
			password = value
		}
		u.User = url.User(u.User.Username())
	}
	query.Del("password")
	if overrideDatabase != "" {
		u.Path = "/" + overrideDatabase
		u.RawPath = ""
		query.Del("dbname")
	}
	u.RawQuery = query.Encode()
	return []string{"PGDATABASE=" + u.String(), "PGPASSWORD=" + password, "PGCONNECT_TIMEOUT=5"}, nil
}

func (m *Manager) backupNames() ([]string, error) {
	entries, err := os.ReadDir(filepath.Join(m.data, "backups"))
	if os.IsNotExist(err) {
		return []string{}, nil
	}
	if err != nil {
		return nil, err
	}
	names := []string{}
	for _, entry := range entries {
		if entry.Type().IsRegular() && backupNamePattern.MatchString(entry.Name()) {
			names = append(names, entry.Name())
		}
	}
	sort.Sort(sort.Reverse(sort.StringSlice(names)))
	return names, nil
}

func (m *Manager) verifiedBackup(name string) (*os.File, error) {
	if !backupNamePattern.MatchString(name) {
		return nil, errors.New("请选择管理器备份目录中的数据库备份")
	}
	dir := filepath.Join(m.data, "backups")
	for _, file := range []string{name, name + ".sha256"} {
		info, err := os.Lstat(filepath.Join(dir, file))
		if err != nil || !info.Mode().IsRegular() {
			return nil, errors.New("备份或 SHA-256 文件不存在，或不是普通文件")
		}
	}
	checksum, err := os.ReadFile(filepath.Join(dir, name+".sha256"))
	if err != nil {
		return nil, err
	}
	fields := strings.Fields(string(checksum))
	if len(fields) != 2 || fields[1] != name {
		return nil, errors.New("备份 SHA-256 文件格式无效")
	}
	expected, err := hex.DecodeString(fields[0])
	if err != nil || len(expected) != sha256.Size {
		return nil, errors.New("备份 SHA-256 文件格式无效")
	}
	f, err := os.Open(filepath.Join(dir, name))
	if err != nil {
		return nil, err
	}
	hash := sha256.New()
	if _, err := io.Copy(hash, f); err != nil {
		f.Close()
		return nil, err
	}
	if !strings.EqualFold(hex.EncodeToString(hash.Sum(nil)), fields[0]) {
		f.Close()
		return nil, errors.New("备份 SHA-256 不匹配；未执行恢复")
	}
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		f.Close()
		return nil, err
	}
	return f, nil
}

// RestoreCheck only restores manager-owned backups to a newly created target.
// The live database is never passed as a pg_restore target.
func (m *Manager) RestoreCheck(ctx context.Context, name string) (string, error) {
	if !m.mu.TryLock() {
		return "", errors.New("另一个管理操作正在执行，请稍后重试")
	}
	defer m.mu.Unlock()
	f, err := m.verifiedBackup(name)
	if err != nil {
		return "", err
	}
	defer f.Close()
	suffix, err := randomHex(8)
	if err != nil {
		return "", err
	}
	if m.cfg.Mode == "docker" {
		return m.restoreDocker(ctx, f, "pactick-restore-"+suffix)
	}
	return m.restoreNative(ctx, f, "pactick_restore_"+suffix)
}

func (m *Manager) restoreNative(ctx context.Context, source io.Reader, target string) (message string, resultErr error) {
	pool, err := database.Open(ctx, m.cfg.DatabaseURL, 1)
	if err != nil {
		return "", errors.New("无法连接数据库进行恢复检查")
	}
	defer pool.Close()
	if _, err := pool.Exec(ctx, "CREATE DATABASE "+pgx.Identifier{target}.Sanitize()); err != nil {
		return "", errors.New("创建隔离恢复数据库失败；数据库账户需要 CREATEDB 权限，原数据库未修改")
	}
	defer func() {
		cleanup, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		if _, err := pool.Exec(cleanup, "DROP DATABASE "+pgx.Identifier{target}.Sanitize()+" WITH (FORCE)"); err != nil {
			resultErr = fmt.Errorf("恢复检查目标 %s 清理失败，请手工删除该临时数据库；原数据库未覆盖", target)
		}
	}()
	env, err := postgresEnvironment(m.cfg.DatabaseURL, target)
	if err != nil {
		return "", err
	}
	cmd := exec.CommandContext(ctx, "pg_restore", "--no-password", "--exit-on-error", "--no-owner", "--no-privileges", "--dbname="+env[0][len("PGDATABASE="):])
	// PGDATABASE is also used by pg_restore; the option is a password-free URI.
	cmd.Env = mergeEnvironment(env)
	cmd.Stdin = source
	var output cappedBuffer
	cmd.Stdout, cmd.Stderr = &output, &output
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("隔离恢复失败：%s", m.redact(output.String()))
	}
	u, _ := url.Parse(m.cfg.DatabaseURL)
	u.Path, u.RawPath = "/"+target, ""
	q := u.Query()
	q.Del("dbname")
	u.RawQuery = q.Encode()
	restored, err := database.Open(ctx, u.String(), 1)
	if err != nil {
		return "", errors.New("无法检查已恢复数据库")
	}
	defer restored.Close()
	if err := database.VerifyMigrations(ctx, restored); err != nil {
		return "", fmt.Errorf("恢复后迁移账本与当前程序不一致：%s", m.redact(err.Error()))
	}
	var count int
	if err := restored.QueryRow(ctx, "SELECT count(*) FROM users").Scan(&count); err != nil {
		return "", errors.New("恢复后无法读取账户表")
	}
	return fmt.Sprintf("隔离恢复检查通过，账户数 %d；临时数据库已清理，当前数据库未覆盖。", count), nil
}

func (m *Manager) restoreDocker(ctx context.Context, source io.Reader, target string) (message string, resultErr error) {
	secret, err := randomHex(24)
	if err != nil {
		return "", err
	}
	envFile := filepath.Join(m.data, ".restore-"+target+".env")
	if err := writePrivate(envFile, []byte("POSTGRES_USER=pactick\nPOSTGRES_DB=pactick\nPOSTGRES_PASSWORD="+secret+"\n")); err != nil {
		return "", err
	}
	defer os.Remove(envFile)
	if _, err := m.run(ctx, nil, nil, "docker", "volume", "create", target); err != nil {
		return "", err
	}
	defer func() {
		cleanup, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		_, containerErr := m.run(cleanup, nil, nil, "docker", "rm", "-f", target)
		_, volumeErr := m.run(cleanup, nil, nil, "docker", "volume", "rm", target)
		if containerErr != nil || volumeErr != nil {
			resultErr = fmt.Errorf("恢复检查目标 %s 清理失败，请检查同名临时容器和卷；当前数据库未覆盖", target)
		}
	}()
	if _, err := m.run(ctx, nil, nil, "docker", "run", "-d", "--name", target, "--network", "none", "--env-file", envFile, "--mount", "type=volume,source="+target+",target=/var/lib/postgresql/data", "postgres:17-alpine"); err != nil {
		return "", err
	}
	ready := false
	for i := 0; i < 45; i++ {
		if _, err := m.run(ctx, nil, nil, "docker", "exec", target, "pg_isready", "-U", "pactick", "-d", "pactick"); err == nil {
			ready = true
			break
		}
		select {
		case <-ctx.Done():
			return "", ctx.Err()
		case <-time.After(time.Second):
		}
	}
	if !ready {
		return "", errors.New("隔离恢复数据库未就绪")
	}
	cmd := exec.CommandContext(ctx, "docker", "exec", "-i", target, "pg_restore", "--exit-on-error", "--no-owner", "--no-privileges", "-U", "pactick", "-d", "pactick")
	cmd.Stdin = source
	var output cappedBuffer
	cmd.Stdout, cmd.Stderr = &output, &output
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("隔离恢复失败：%s", m.redact(output.String()))
	}
	if _, err := m.run(ctx, nil, nil, "docker", "exec", target, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "pactick", "-d", "pactick", "-At", "-c", "SELECT count(*) FROM users; SELECT count(*) FROM schema_migrations WHERE checksum IS NOT NULL;"); err != nil {
		return "", err
	}
	return "隔离恢复检查通过，迁移账本和账户表可读取；临时容器及卷已清理，当前数据库未覆盖。", nil
}
