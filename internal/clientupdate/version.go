package clientupdate

import (
	"errors"
	"strings"
)

const maxVersionLength = 64

type semanticVersion struct {
	core       [3]string
	prerelease []string
}

// ValidateVersion validates the SemVer subset used by the update contract.
// Build metadata is deliberately excluded because build_number is separate.
func ValidateVersion(value string) error {
	_, err := parseVersion(value)
	return err
}

func parseVersion(value string) (semanticVersion, error) {
	if value == "" || len(value) > maxVersionLength {
		return semanticVersion{}, errors.New("must contain between 1 and 64 characters")
	}
	if strings.Contains(value, "+") {
		return semanticVersion{}, errors.New("build metadata is not allowed; use build_number")
	}

	corePart, prereleasePart, hasPrerelease := strings.Cut(value, "-")
	coreIdentifiers := strings.Split(corePart, ".")
	if len(coreIdentifiers) != 3 {
		return semanticVersion{}, errors.New("must use major.minor.patch format")
	}
	var version semanticVersion
	for index, identifier := range coreIdentifiers {
		if !validNumericIdentifier(identifier) {
			return semanticVersion{}, errors.New("core identifiers must be decimal integers without leading zeroes")
		}
		version.core[index] = identifier
	}

	if hasPrerelease {
		if prereleasePart == "" {
			return semanticVersion{}, errors.New("prerelease identifiers must not be empty")
		}
		version.prerelease = strings.Split(prereleasePart, ".")
		for _, identifier := range version.prerelease {
			if !validPrereleaseIdentifier(identifier) {
				return semanticVersion{}, errors.New("prerelease identifiers must use ASCII letters, digits, or hyphens")
			}
			if allDigits(identifier) && len(identifier) > 1 && identifier[0] == '0' {
				return semanticVersion{}, errors.New("numeric prerelease identifiers must not contain leading zeroes")
			}
		}
	}
	return version, nil
}

// CompareVersions compares two validated semantic versions and returns -1, 0,
// or 1 when left is respectively older than, equal to, or newer than right.
func CompareVersions(left, right string) (int, error) {
	leftVersion, err := parseVersion(left)
	if err != nil {
		return 0, err
	}
	rightVersion, err := parseVersion(right)
	if err != nil {
		return 0, err
	}

	for index := range leftVersion.core {
		if comparison := compareNumericIdentifier(leftVersion.core[index], rightVersion.core[index]); comparison != 0 {
			return comparison, nil
		}
	}
	if len(leftVersion.prerelease) == 0 && len(rightVersion.prerelease) == 0 {
		return 0, nil
	}
	if len(leftVersion.prerelease) == 0 {
		return 1, nil
	}
	if len(rightVersion.prerelease) == 0 {
		return -1, nil
	}

	commonLength := min(len(leftVersion.prerelease), len(rightVersion.prerelease))
	for index := 0; index < commonLength; index++ {
		leftIdentifier := leftVersion.prerelease[index]
		rightIdentifier := rightVersion.prerelease[index]
		leftNumeric := allDigits(leftIdentifier)
		rightNumeric := allDigits(rightIdentifier)
		switch {
		case leftNumeric && rightNumeric:
			if comparison := compareNumericIdentifier(leftIdentifier, rightIdentifier); comparison != 0 {
				return comparison, nil
			}
		case leftNumeric:
			return -1, nil
		case rightNumeric:
			return 1, nil
		case leftIdentifier < rightIdentifier:
			return -1, nil
		case leftIdentifier > rightIdentifier:
			return 1, nil
		}
	}
	switch {
	case len(leftVersion.prerelease) < len(rightVersion.prerelease):
		return -1, nil
	case len(leftVersion.prerelease) > len(rightVersion.prerelease):
		return 1, nil
	default:
		return 0, nil
	}
}

func validNumericIdentifier(value string) bool {
	return value != "" && allDigits(value) && (len(value) == 1 || value[0] != '0')
}

func validPrereleaseIdentifier(value string) bool {
	if value == "" {
		return false
	}
	for index := range len(value) {
		character := value[index]
		if (character < '0' || character > '9') &&
			(character < 'A' || character > 'Z') &&
			(character < 'a' || character > 'z') && character != '-' {
			return false
		}
	}
	return true
}

func allDigits(value string) bool {
	if value == "" {
		return false
	}
	for index := range len(value) {
		if value[index] < '0' || value[index] > '9' {
			return false
		}
	}
	return true
}

func compareNumericIdentifier(left, right string) int {
	switch {
	case len(left) < len(right):
		return -1
	case len(left) > len(right):
		return 1
	case left < right:
		return -1
	case left > right:
		return 1
	default:
		return 0
	}
}
