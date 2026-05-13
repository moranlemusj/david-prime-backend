"""Tiny Python greeter — fixture for oracle-index tests."""


def greet(name: str) -> str:
    return _format_greeting(name)


def _format_greeting(name: str) -> str:
    return f"Hello, {name}!"
