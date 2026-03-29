package metrics

import (
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// ProcessMetrics holds top process information.
type ProcessMetrics struct {
	Timestamp  time.Time `json:"timestamp"`
	TotalProcs int       `json:"total_processes"`
	Running    int       `json:"running"`
	Sleeping   int       `json:"sleeping"`
	TopByCPU   []Process `json:"top_by_cpu"`
	TopByMem   []Process `json:"top_by_memory"`
}

// Process represents a single process.
type Process struct {
	PID     int     `json:"pid"`
	User    string  `json:"user"`
	CPUPct  float64 `json:"cpu_percent"`
	MemPct  float64 `json:"mem_percent"`
	RSS     uint64  `json:"rss_bytes"`
	Command string  `json:"command"`
	State   string  `json:"state"`
}

// CollectProcesses gathers top processes by CPU and memory.
func CollectProcesses() (*ProcessMetrics, error) {
	m := &ProcessMetrics{
		Timestamp: time.Now().UTC(),
	}

	// Top 15 by CPU
	topCPU, err := exec.Command("ps", "aux", "--sort=-pcpu").Output()
	if err != nil {
		return nil, err
	}
	cpuLines := strings.Split(string(topCPU), "\n")
	for i, line := range cpuLines {
		if i == 0 { // skip header
			continue
		}
		p, ok := parsePSLine(line)
		if !ok {
			continue
		}
		m.TotalProcs++
		switch p.State {
		case "R":
			m.Running++
		case "S":
			m.Sleeping++
		}
		if len(m.TopByCPU) < 15 {
			m.TopByCPU = append(m.TopByCPU, p)
		}
	}

	// Top 15 by memory
	topMem, err := exec.Command("ps", "aux", "--sort=-rss").Output()
	if err != nil {
		return nil, err
	}
	memLines := strings.Split(string(topMem), "\n")
	for i, line := range memLines {
		if i == 0 {
			continue
		}
		p, ok := parsePSLine(line)
		if !ok {
			continue
		}
		if len(m.TopByMem) < 15 {
			m.TopByMem = append(m.TopByMem, p)
		}
	}

	return m, nil
}

// parsePSLine parses a line of `ps aux` output.
// Format: USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND
func parsePSLine(line string) (Process, bool) {
	fields := strings.Fields(line)
	if len(fields) < 11 {
		return Process{}, false
	}

	pid, _ := strconv.Atoi(fields[1])
	cpuPct, _ := strconv.ParseFloat(fields[2], 64)
	memPct, _ := strconv.ParseFloat(fields[3], 64)
	rss, _ := strconv.ParseUint(fields[5], 10, 64)

	state := ""
	if len(fields[7]) > 0 {
		state = string(fields[7][0])
	}

	// Command is everything from field 10 onward
	cmd := strings.Join(fields[10:], " ")
	// Truncate long commands
	if len(cmd) > 120 {
		cmd = cmd[:120] + "..."
	}

	return Process{
		PID:     pid,
		User:    fields[0],
		CPUPct:  cpuPct,
		MemPct:  memPct,
		RSS:     rss * 1024, // kB -> bytes
		Command: cmd,
		State:   state,
	}, true
}
