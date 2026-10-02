package auth

import "testing"

func TestPasswordHasherRoundTrip(t *testing.T) {
	hasher := PasswordHasher{Memory: 8 * 1024, Iterations: 1, Parallelism: 1, SaltLength: 16, KeyLength: 32}
	encoded, err := hasher.Hash("correct horse battery staple")
	if err != nil {
		t.Fatalf("Hash() error = %v", err)
	}
	matched, err := hasher.Verify("correct horse battery staple", encoded)
	if err != nil {
		t.Fatalf("Verify() error = %v", err)
	}
	if !matched {
		t.Fatal("Verify() did not match the original password")
	}
	matched, err = hasher.Verify("wrong password", encoded)
	if err != nil {
		t.Fatalf("Verify() wrong password error = %v", err)
	}
	if matched {
		t.Fatal("Verify() matched a different password")
	}
}

func TestPasswordHasherRejectsUnsafeParameters(t *testing.T) {
	hasher := DefaultPasswordHasher()
	matched, err := hasher.Verify("password", "$argon2id$v=19$m=2000000,t=1,p=1$c2FsdA$a2V5")
	if err == nil || matched {
		t.Fatal("Verify() accepted unsafe hash parameters")
	}
}
