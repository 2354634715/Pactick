package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"pactick/server/internal/admin"
	"pactick/server/internal/auth"
)

func TestCommandUsesStdinForPasswordAndReturnsOnlyAccount(t *testing.T) {
	const password = "supplied-password-marker"
	var output bytes.Buffer
	called := false
	create := func(_ context.Context, databaseURL string, request admin.CreateAccountRequest) (admin.CreateAccountResult, error) {
		called = true
		if databaseURL != "database-url-marker" || request.Email != "alice@example.invalid" || request.Password != password {
			t.Fatal("stdin or database configuration was not passed correctly")
		}
		return admin.CreateAccountResult{User: auth.User{ID: "user-id", Email: request.Email}}, nil
	}
	exitCode := run(context.Background(), []string{"create-account"}, strings.NewReader(`{"email":"alice@example.invalid","password":"`+password+`"}`), &output, func(key string) string {
		if key != "DATABASE_URL" {
			t.Fatalf("unexpected environment key %q", key)
		}
		return "database-url-marker"
	}, create)
	var result response
	if err := json.Unmarshal(output.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if exitCode != 0 || !called || !result.OK || result.User.Email != "alice@example.invalid" || strings.Contains(output.String(), password) || strings.Contains(output.String(), "database-url-marker") {
		t.Fatal("command returned an incorrect or sensitive result")
	}
}

func TestCommandRejectsArgumentsAndJSONWithoutCallingDatabase(t *testing.T) {
	const secret = "argument-password-marker"
	for _, test := range []struct {
		args  []string
		input string
	}{
		{nil, ""},
		{[]string{"create-account", "--password", secret}, "{}"},
		{[]string{"create-account"}, `{"unknown":"` + secret + `"}`},
	} {
		var output bytes.Buffer
		exitCode := run(context.Background(), test.args, strings.NewReader(test.input), &output,
			func(string) string { t.Fatal("invalid input accessed configuration"); return "" },
			func(context.Context, string, admin.CreateAccountRequest) (admin.CreateAccountResult, error) {
				t.Fatal("invalid input called account creation")
				return admin.CreateAccountResult{}, nil
			})
		var result response
		if err := json.Unmarshal(output.Bytes(), &result); err != nil {
			t.Fatal(err)
		}
		if exitCode != 2 || result.OK || result.Error == nil || strings.Contains(output.String(), secret) {
			t.Fatal("invalid command returned an incorrect or sensitive result")
		}
	}
}

func TestCommandPreservesSafeErrorAndSuppressesUnexpectedDetails(t *testing.T) {
	for _, test := range []struct {
		err  error
		code string
	}{
		{&admin.Error{Code: "email_taken", Message: "该邮箱已注册。"}, "email_taken"},
		{errors.New("database-password-marker"), "account_creation_failed"},
	} {
		var output bytes.Buffer
		exitCode := run(context.Background(), []string{"create-account"}, strings.NewReader(`{"email":"alice@example.invalid"}`), &output, func(string) string { return "" },
			func(context.Context, string, admin.CreateAccountRequest) (admin.CreateAccountResult, error) {
				return admin.CreateAccountResult{}, test.err
			})
		var result response
		if err := json.Unmarshal(output.Bytes(), &result); err != nil {
			t.Fatal(err)
		}
		if exitCode != 1 || result.OK || result.Error == nil || result.Error.Code != test.code || strings.Contains(output.String(), "database-password-marker") {
			t.Fatal("backend failure returned unsafe details")
		}
	}
}
