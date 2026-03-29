package metrics

import (
	"fmt"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"time"
)

// PerformanceMetrics holds CPU, memory, load, and uptime data.
type PerformanceMetrics struct {
	Hostname    string    `json:"hostname"`
	Timestamp   time.Time `json:"timestamp"`
	CPUPercent  float64   `json:"cpu_percent"`
	MemoryTotal uint64    `json:"memory_total_bytes"`
	MemoryUsed  uint64    `json:"memory_used_bytes"`
	MemoryFree  uint64    `json:"memory_free_bytes"`
	MemoryPct   float64   `json:"memory_used_percent"`
	LoadAvg1    float64   `json:"load_avg_1"`
	LoadAvg5    float64   `json:"load_avg_5"`
	LoadAvg15   float64   `json:"load_avg_15"`
	UptimeSecs  float64   `json:"uptime_seconds"`
	NumCPUs     int       `json:"num_cpus"`
}

// CollectPerformance gathers live performance metrics from the host.
func CollectPerformance() (*PerformanceMetrics, error) {
	m := &PerformanceMetrics{
		Timestamp: time.Now().UTC(),
		NumCPUs:   runtime.NumCPU(),
	}

	// Hostname
	out, err := exec.Command("hostname").Output()
	if err == nil {
		m.Hostname = strings.TrimSpace(string(out))
	}

	// CPU usage from /proc/stat (two samples 1s apart)
	cpuPct, err := sampleCPU()
	if err == nil {
		m.CPUPercent = cpuPct
	}

	// Memory from /proc/meminfo
	if err := parseMeminfo(m); err != nil {
		return nil, fmt.Errorf("meminfo: %w", err)
	}

	// Load averages from /proc/loadavg
	if err := parseLoadavg(m); err != nil {
		return nil, fmt.Errorf("loadavg: %w", err)
	}

	// Uptime from /proc/uptime
	if err := parseUptime(m); err != nil {
		return nil, fmt.Errorf("uptime: %w", err)
	}

	return m, nil
}

// sampleCPU reads /proc/stat twice with a 1-second gap to compute CPU%.
func sampleCPU() (float64, error) {
	read := func() (idle, total uint64, err error) {
		out, err := exec.Command("cat", "/proc/stat").Output()
		if err != nil {
			return 0, 0, err
		}
		lines := strings.Split(string(out), "\n")
		for _, line := range lines {
			if strings.HasPrefix(line, "cpu ") {
				fields := strings.Fields(line)
				if len(fields) < 5 {
					return 0, 0, fmt.Errorf("unexpected /proc/stat format")
				}
				var vals []uint64
				for _, f := range fields[1:] {
					v, _ := strconv.ParseUint(f, 10, 64)
					vals = append(vals, v)
				}
				for _, v := range vals {
					total += v
				}
				if len(vals) >= 4 {
					idle = vals[3]
				}
				return idle, total, nil
			}
		}
		return 0, 0, fmt.Errorf("/proc/stat: no cpu line")
	}

	idle1, total1, err := read()
	if err != nil {
		return 0, err
	}
	time.Sleep(1 * time.Second)
	idle2, total2, err := read()
	if err != nil {
		return 0, err
	}

	totalDelta := float64(total2 - total1)
	idleDelta := float64(idle2 - idle1)
	if totalDelta == 0 {
		return 0, nil
	}
	return ((totalDelta - idleDelta) / totalDelta) * 100, nil
}

func parseMeminfo(m *PerformanceMetrics) error {
	out, err := exec.Command("cat", "/proc/meminfo").Output()
	if err != nil {
		return err
	}
	vals := make(map[string]uint64)
	for _, line := range strings.Split(string(out), "\n") {
		parts := strings.Fields(line)
		if len(parts) >= 2 {
			key := strings.TrimSuffix(parts[0], ":")
			v, _ := strconv.ParseUint(parts[1], 10, 64)
			vals[key] = v * 1024 // kB -> bytes
		}
	}
	m.MemoryTotal = vals["MemTotal"]
	m.MemoryFree = vals["MemAvailable"]
	if m.MemoryFree == 0 {
		m.MemoryFree = vals["MemFree"] + vals["Buffers"] + vals["Cached"]
	}
	m.MemoryUsed = m.MemoryTotal - m.MemoryFree
	if m.MemoryTotal > 0 {
		m.MemoryPct = (float64(m.MemoryUsed) / float64(m.MemoryTotal)) * 100
	}
	return nil
}

func parseLoadavg(m *PerformanceMetrics) error {
	out, err := exec.Command("cat", "/proc/loadavg").Output()
	if err != nil {
		return err
	}
	fields := strings.Fields(string(out))
	if len(fields) >= 3 {
		m.LoadAvg1, _ = strconv.ParseFloat(fields[0], 64)
		m.LoadAvg5, _ = strconv.ParseFloat(fields[1], 64)
		m.LoadAvg15, _ = strconv.ParseFloat(fields[2], 64)
	}
	return nil
}

func parseUptime(m *PerformanceMetrics) error {
	out, err := exec.Command("cat", "/proc/uptime").Output()
	if err != nil {
		return err
	}
	fields := strings.Fields(string(out))
	if len(fields) >= 1 {
		m.UptimeSecs, _ = strconv.ParseFloat(fields[0], 64)
	}
	return nil
}
