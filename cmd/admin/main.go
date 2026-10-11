package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/signal"
	"syscall"

	"pactick/server/internal/admin"
)

type createAccountFunc func(context.Context, string, admin.CreateAccountRequest) (admin.CreateAccountResult, error)

type response struct {
	OK bool `json:"ok"`
	*admin.CreateAccountResult
	Error *admin.Error `json:"error,omitempty"`
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	os.Exit(run(ctx, os.Args[1:], os.Stdin, os.Stdout, os.Getenv, admin.CreateAccount))
}

func run(ctx context.Context, args []string, input io.Reader, output io.Writer, getenv func(string) string, create createAccountFunc) int {
	if len(args) == 1 && (args[0] == "--help" || args[0] == "-h") {
		_, err := io.WriteString(output, "用法：pactick-admin create-account\n从标准输入读取单个 UTF-8 JSON 对象，结果以 JSON 输出。\n必填：email。可选：password、display_name、time_zone、locale、week_starts_on。\n空密码将自动生成；默认时区 UTC、语言 zh-CN、每周从周一开始。\n数据库连接使用 DATABASE_URL；请先执行数据库迁移。\n密码不得放入命令行参数。\n")
		if err != nil {
			return 1
		}
		return 0
	}
	if len(args) != 1 || args[0] != "create-account" {
		return writeFailure(output, &admin.Error{Code: "invalid_command", Message: "使用 pactick-admin create-account，通过标准输入提供账户 JSON；使用 --help 查看字段。"}, 2)
	}
	request, err := admin.DecodeCreateAccountRequest(input)
	if err != nil {
		return writeFailure(output, err, 2)
	}
	result, err := create(ctx, getenv("DATABASE_URL"), request)
	if err != nil {
		return writeFailure(output, err, 1)
	}
	if err := json.NewEncoder(output).Encode(response{OK: true, CreateAccountResult: &result}); err != nil {
		return 1
	}
	return 0
}

func writeFailure(output io.Writer, err error, exitCode int) int {
	var safeError *admin.Error
	if !errors.As(err, &safeError) {
		safeError = &admin.Error{Code: "account_creation_failed", Message: "创建账户失败。"}
	}
	if err := json.NewEncoder(output).Encode(response{Error: safeError}); err != nil {
		return 1
	}
	return exitCode
}
