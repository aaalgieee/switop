# SWITOP - System Performance Monitor

📊 Monitor your Mac's performance with detailed insights into CPU, GPU, memory, and power metrics. Built with Swift, optimized for Apple Silicon.

SWITOP is a powerful command-line interface (CLI) application designed to provide real-time system performance monitoring for Apple Silicon Macs. It offers detailed insights into CPU, GPU, memory usage, and power consumption metrics.

## Features

- **CPU Monitoring**
  - E-Core and P-Core usage percentages and frequencies
  - Real-time performance metrics for both efficiency and performance cores

- **GPU Monitoring**
  - GPU usage percentage and frequency
  - Real-time GPU performance metrics

- **Memory Statistics**
  - Physical memory usage
  - Swap memory utilization
  - Detailed memory breakdown

- **Power Consumption Metrics**
  - CPU power usage in watts
  - GPU power consumption
  - ANE (Apple Neural Engine) power usage
  - Combined power consumption

## Requirements

- macOS running on Apple Silicon (M1 or later)
- Root/Administrator privileges (for accessing system metrics)
- Xcode 14.0+ (for building from source)

## Installation

### Building from Source

1. Clone the repository:
```bash
git clone https://github.com/yourusername/switop.git
cd switop
```

2. Build the project:
```bash
swift build -c release
```

3. The binary will be available in `.build/release/switop`

## Usage

Simply run the application from the terminal:

```bash
sudo ./switop
```

Note: Root privileges are required to access system performance metrics.

### Interface

The application displays:
- System information including CPU model and core configuration
- Real-time CPU metrics for both E-cores and P-cores
- GPU usage and frequency
- Memory usage statistics
- Detailed power consumption metrics

Use `Ctrl+C` to exit the application.

## Technical Details

SWITOP utilizes various system APIs and commands:
- `powermetrics` for CPU and GPU metrics
- `vm_stat` for memory statistics
- `sysctl` for system information
- System profiler for GPU information

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

If you encounter any issues or have questions, please file an issue on the GitHub repository.
