# Orchard

[![Hex.pm](https://img.shields.io/hexpm/v/orchard.svg)](https://hex.pm/packages/orchard)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/orchard)
[![License](https://img.shields.io/hexpm/l/orchard.svg)](https://github.com/tuist/orchard/blob/main/LICENSE)
[![Downloads](https://img.shields.io/hexpm/dt/orchard.svg)](https://hex.pm/packages/orchard)
[![Elixir](https://img.shields.io/badge/elixir-%E2%89%A5%201.14-purple.svg)](https://elixir-lang.org/)

An Elixir package for managing Apple simulators with automatic lifecycle management using OTP supervision trees. Built on top of [AXe](https://github.com/cameroncooke/AXe) for UI automation and Apple's simctl for simulator control.

## Requirements

- **macOS only** - Apple device management requires macOS
- Xcode Command Line Tools
- Elixir 1.14 or later

## Installation

Add `orchard` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:orchard, "~> 0.1.0"}
  ]
end
```

On first use, Orchard will automatically download the AXe CLI binary. You can also manually download it:

```bash
mix orchard.download
```

### Configuration

You can configure the AXe version or provide a custom path:

```elixir
# config/config.exs
config :orchard,
  axe_version: "1.0.0",  # Optional: specify AXe version
  axe_path: "/usr/local/bin/AXe"  # Optional: use custom AXe binary
```

## Usage

```elixir
# List all simulators
{:ok, simulators} = Orchard.Simulator.list()

# Boot a simulator (starts a GenServer to manage it)
{:ok, simulator} = Orchard.Simulator.boot(simulator)

# The simulator is now managed by a GenServer that:
# - Monitors its state every second
# - Automatically terminates if the simulator is removed
# - Provides a supervised process for all operations

# Install an app on a simulator
:ok = Orchard.Simulator.install_app(simulator, "/path/to/app.app")

# UI Automation with AXe
:ok = Orchard.Simulator.tap(simulator, 100, 200)
:ok = Orchard.Simulator.type_text(simulator, "Hello World")
{:ok, ui_tree} = Orchard.Simulator.describe_ui(simulator)

# Take a screenshot
:ok = Orchard.Simulator.screenshot(simulator, "/tmp/screenshot.png")

# Shutdown the simulator
:ok = Orchard.Simulator.shutdown(simulator)
```

## Architecture

Orchard uses Erlang/OTP supervision trees to manage simulators:

- Each booted simulator runs in its own `SimulatorServer` GenServer
- The `SimulatorSupervisor` manages all simulator processes
- Simulators are automatically monitored and cleaned up
- Crashed processes are restarted by the supervisor

## Features

### Simulator Management
- List all available simulators
- Boot and shutdown simulators
- Install and launch apps
- Automatic state monitoring via GenServers
- Supervised processes with automatic cleanup

### UI Automation (via AXe)
- Tap at specific coordinates
- Type text
- Swipe gestures
- Hardware button presses
- Get accessibility hierarchy information

### System Integration
- Screenshot capture
- Video recording
- App installation/uninstallation
- Process supervision with MuonTrap

### Platform Support
- **macOS only** - Requires Apple developer tools
- Automatic AXe CLI download and management
- Fails gracefully on unsupported platforms

## How It Works

Orchard combines several technologies:

1. **[AXe CLI](https://github.com/cameroncooke/AXe)** - For UI automation and simulator listing
2. **Apple's simctl** - For simulator control operations
3. **Erlang/OTP** - For process supervision and state management
4. **MuonTrap** - For reliable system process management

When you boot a simulator, Orchard:
1. Starts a dedicated GenServer process for that simulator
2. Monitors the simulator's state every second
3. Automatically cleans up if the simulator is removed
4. Provides a consistent interface for all operations

The AXe binary is automatically downloaded on first use or can be manually downloaded using `mix orchard.download`.

## License

MIT