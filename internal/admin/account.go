// Package admin implements trusted local administration without HTTP endpoints.
package admin

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"strings"
	"time"
	_ "time/tzdata"
	"unicode/utf8"

	"pactick/server/internal/auth"
	"pactick/server/internal/database"
)

const maxRequestBytes = 32 * 1024

type CreateAccountRequest struct {
	Email        string `json:"email"`
	Password     string `json:"password,omitempty"`
	DisplayName  string `json:"display_name,omitempty"`
	TimeZone     string `json:"time_zone,omitempty"`
	Locale       string `json:"locale,omitempty"`
	WeekStartsOn *int   `json:"week_starts_on,omitempty"`
}

type CreateAccountResult struct {
	User              auth.User `json:"user"`
	GeneratedPassword string    `json:"generated_password,omitempty"`
}

// Error contains safe operator-facing details, never a database DSN or password.
type Error struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func (e *Error) Error() string { return e.Message }

// DecodeCreateAccountRequest accepts one UTF-8 JSON object, at most 32 KiB.
// Parse errors deliberately omit the submitted data.
func DecodeCreateAccountRequest(reader io.Reader) (CreateAccountRequest, error) {
	contents, err := io.ReadAll(io.LimitReader(reader, maxRequestBytes+1))
	if err != nil {
		return CreateAccountRequest{}, &Error{Code: "invalid_json", Message: "无法读取账户参数。"}
	}
	if len(contents) > maxRequestBytes || !utf8.Valid(contents) {
		return CreateAccountRequest{}, &Error{Code: "invalid_json", Message: "账户参数必须是单个 UTF-8 JSON 对象，且不超过 32 KiB。"}
	}
	contents = bytes.TrimSpace(contents)
	if len(contents) == 0 || contents[0] != '{' {
		return CreateAccountRequest{}, &Error{Code: "invalid_json", Message: "账户参数必须是单个 UTF-8 JSON 对象，且不超过 32 KiB。"}
	}
	decoder := json.NewDecoder(bytes.NewReader(contents))
	decoder.DisallowUnknownFields()
	var request CreateAccountRequest
	if err := decoder.Decode(&request); err != nil {
		return CreateAccountRequest{}, &Error{Code: "invalid_json", Message: "账户 JSON 格式、字段名称或字段类型无效。"}
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return CreateAccountRequest{}, &Error{Code: "invalid_json", Message: "账户参数只能包含一个 JSON 对象。"}
	}
	return request, nil
}

func prepareAccount(request CreateAccountRequest) (auth.AccountInput, string, error) {
	generatedPassword := ""
	if request.Password == "" {
		var secret [24]byte
		if _, err := rand.Read(secret[:]); err != nil {
			return auth.AccountInput{}, "", &Error{Code: "password_generation_failed", Message: "无法生成账户密码。"}
		}
		generatedPassword = base64.RawURLEncoding.EncodeToString(secret[:])
		request.Password = generatedPassword
	}
	if strings.TrimSpace(request.DisplayName) == "" {
		request.DisplayName, _, _ = strings.Cut(strings.TrimSpace(request.Email), "@")
	}
	if strings.TrimSpace(request.TimeZone) == "" {
		request.TimeZone = "UTC"
	}
	weekStartsOn := 1
	if request.WeekStartsOn != nil {
		weekStartsOn = *request.WeekStartsOn
	}
	input, err := auth.NormalizeAccountInput(auth.AccountInput{
		Email: request.Email, Password: request.Password, DisplayName: request.DisplayName,
		TimeZone: request.TimeZone, Locale: request.Locale, WeekStartsOn: weekStartsOn,
	})
	if err != nil {
		return auth.AccountInput{}, "", safeAccountError(err)
	}
	return input, generatedPassword, nil
}

// CreateAccount connects directly to PostgreSQL using the server's database URL.
// Migrations must already be current. No device, session or access token is created.
// An omitted or empty password is generated and returned only after successful creation.
func CreateAccount(ctx context.Context, databaseURL string, request CreateAccountRequest) (CreateAccountResult, error) {
	input, generatedPassword, err := prepareAccount(request)
	if err != nil {
		return CreateAccountResult{}, err
	}
	if strings.TrimSpace(databaseURL) == "" {
		return CreateAccountResult{}, &Error{Code: "configuration_required", Message: "请配置 DATABASE_URL 后创建账户。"}
	}
	ctx, cancel := context.WithTimeout(ctx, 45*time.Second)
	defer cancel()
	pool, err := database.Open(ctx, databaseURL, 2)
	if err != nil {
		if ctx.Err() != nil {
			return CreateAccountResult{}, safeAccountError(ctx.Err())
		}
		return CreateAccountResult{}, &Error{Code: "database_unavailable", Message: "无法连接数据库。请检查数据库服务、DATABASE_URL 和访问权限。"}
	}
	defer pool.Close()
	if err := database.VerifyMigrations(ctx, pool); err != nil {
		if ctx.Err() != nil {
			return CreateAccountResult{}, safeAccountError(ctx.Err())
		}
		return CreateAccountResult{}, &Error{Code: "schema_not_ready", Message: "数据库结构尚未就绪或与当前版本不一致。请先运行数据库迁移。"}
	}
	return provisionAccount(ctx, auth.NewPostgresStore(pool), input, generatedPassword)
}

func provisionAccount(ctx context.Context, store auth.AccountProvisionStore, input auth.AccountInput, generatedPassword string) (CreateAccountResult, error) {
	user, err := auth.NewProvisioner(store).Create(ctx, input)
	if err != nil {
		return CreateAccountResult{}, safeAccountError(err)
	}
	return CreateAccountResult{User: user, GeneratedPassword: generatedPassword}, nil
}

func safeAccountError(err error) error {
	var inputError *auth.InputError
	switch {
	case errors.Is(err, auth.ErrEmailTaken):
		return &Error{Code: "email_taken", Message: "该邮箱已注册。"}
	case errors.As(err, &inputError):
		message := inputError.Message
		if strings.HasPrefix(message, "time_zone is invalid") {
			message = "time_zone is invalid"
		}
		return &Error{Code: "invalid_input", Message: message}
	case errors.Is(err, context.DeadlineExceeded):
		return &Error{Code: "operation_timeout", Message: "创建账户超时。重试前请确认该邮箱是否已创建。"}
	case errors.Is(err, context.Canceled):
		return &Error{Code: "operation_cancelled", Message: "创建账户已取消。重试前请确认该邮箱是否已创建。"}
	default:
		return &Error{Code: "account_creation_failed", Message: "创建账户失败。请检查数据库状态和写入权限。"}
	}
}
