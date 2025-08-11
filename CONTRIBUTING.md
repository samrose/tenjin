# Contributing to Tenjin

Thank you for your interest in contributing to Tenjin! This guide will help you get started.

## Development Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/tenjin-framework/tenjin.git
   cd tenjin
   ```

2. **Enter development environment:**
   ```bash
   nix develop
   ```

3. **Set up development environment:**
   ```bash
   tenjin-dev-setup
   ```

4. **Run tests:**
   ```bash
   mix test
   ```

## Development Workflow

1. **Fork the repository**
2. **Create a feature branch:** `git checkout -b feature/my-feature`
3. **Make your changes**
4. **Add tests** for new functionality
5. **Run the test suite:** `mix test`
6. **Commit your changes:** `git commit -m "Add my feature"`
7. **Push to your fork:** `git push origin feature/my-feature`
8. **Open a Pull Request**

## Code Style

- Follow Elixir formatting conventions
- Use `mix format` to format your code
- Add documentation for public functions
- Write clear commit messages

## Testing

- Add tests for all new functionality
- Run `mix test` before submitting
- Test with both Nix and traditional Elixir environments

## Questions?

Feel free to open an issue if you have questions about contributing!