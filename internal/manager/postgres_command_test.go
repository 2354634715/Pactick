package manager

import (
	"net/url"
	"strings"
	"testing"
)

func TestNativeBackupPassesExplicitConnectionURIWithoutPassword(t *testing.T) {
	for _, address := range []string{
		"postgres://alice:secret%21@127.0.0.1:6543/workspace?sslmode=verify-full&connect_timeout=4",
		"postgres://alice@127.0.0.1:6543/workspace?sslmode=verify-full&connect_timeout=4&password=secret%21",
	} {
		cmd, err := nativeBackupCommand(t.Context(), address)
		if err != nil {
			t.Fatal(err)
		}
		connection := ""
		for _, arg := range cmd.Args[1:] {
			if strings.Contains(arg, "secret") {
				t.Fatal("database password was exposed in process arguments")
			}
			if strings.HasPrefix(arg, "--dbname=") {
				connection = strings.TrimPrefix(arg, "--dbname=")
			}
		}
		if connection == "" {
			t.Fatal("pg_dump needs an explicit dbname URI; PGDATABASE alone does not expand connection parameters")
		}
		u, err := url.Parse(connection)
		if err != nil {
			t.Fatal(err)
		}
		if u.Host != "127.0.0.1:6543" || u.Path != "/workspace" || u.User.Username() != "alice" || u.Query().Get("sslmode") != "verify-full" || u.Query().Get("connect_timeout") != "4" {
			t.Fatal("backup command lost the configured connection target or TLS settings")
		}
		if _, ok := u.User.Password(); ok || u.Query().Has("password") {
			t.Fatal("backup command URI contains a password")
		}
		passwordInEnvironment := false
		for _, entry := range cmd.Env {
			if entry == "PGPASSWORD=secret!" {
				passwordInEnvironment = true
			}
		}
		if !passwordInEnvironment {
			t.Fatal("backup child did not receive its decoded password through PGPASSWORD")
		}
	}
}
