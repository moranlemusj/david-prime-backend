// Package greet is a tiny Go greeter fixture for oracle-index tests.
package greet

// Greet is the public entry point.
func Greet(name string) string {
	return formatGreeting(name)
}

func formatGreeting(name string) string {
	return "Hello, " + name + "!"
}
