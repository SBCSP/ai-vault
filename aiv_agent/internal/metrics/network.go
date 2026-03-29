package metrics

import (
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// NetworkMetrics holds network interface and connection data.
type NetworkMetrics struct {
	Timestamp   time.Time          `json:"timestamp"`
	Interfaces  []NetworkInterface `json:"interfaces"`
	Connections ConnectionSummary  `json:"connections"`
}

// NetworkInterface represents a network interface with traffic stats.
type NetworkInterface struct {
	Name    string `json:"name"`
	State   string `json:"state"`
	RxBytes uint64 `json:"rx_bytes"`
	TxBytes uint64 `json:"tx_bytes"`
	RxPkts  uint64 `json:"rx_packets"`
	TxPkts  uint64 `json:"tx_packets"`
	IPv4    string `json:"ipv4,omitempty"`
}

// ConnectionSummary summarizes active network connections.
type ConnectionSummary struct {
	TCPEstablished int `json:"tcp_established"`
	TCPListening   int `json:"tcp_listening"`
	TCPTimeWait    int `json:"tcp_time_wait"`
	UDPListening   int `json:"udp_listening"`
	Total          int `json:"total"`
}

// CollectNetwork gathers network interface and connection metrics.
func CollectNetwork() (*NetworkMetrics, error) {
	m := &NetworkMetrics{
		Timestamp: time.Now().UTC(),
	}

	// Parse /proc/net/dev for interface stats
	out, err := exec.Command("cat", "/proc/net/dev").Output()
	if err != nil {
		return nil, err
	}
	lines := strings.Split(string(out), "\n")
	for i, line := range lines {
		if i < 2 { // skip headers
			continue
		}
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		colonIdx := strings.Index(line, ":")
		if colonIdx < 0 {
			continue
		}
		name := strings.TrimSpace(line[:colonIdx])
		if name == "lo" {
			continue
		}
		rest := strings.Fields(line[colonIdx+1:])
		if len(rest) < 10 {
			continue
		}

		rxBytes, _ := strconv.ParseUint(rest[0], 10, 64)
		rxPkts, _ := strconv.ParseUint(rest[1], 10, 64)
		txBytes, _ := strconv.ParseUint(rest[8], 10, 64)
		txPkts, _ := strconv.ParseUint(rest[9], 10, 64)

		iface := NetworkInterface{
			Name:    name,
			RxBytes: rxBytes,
			TxBytes: txBytes,
			RxPkts:  rxPkts,
			TxPkts:  txPkts,
		}

		m.Interfaces = append(m.Interfaces, iface)
	}

	// Get IP addresses and link state
	ipOut, err := exec.Command("ip", "-o", "addr", "show").Output()
	if err == nil {
		ifaceMap := make(map[string]*NetworkInterface)
		for idx := range m.Interfaces {
			ifaceMap[m.Interfaces[idx].Name] = &m.Interfaces[idx]
		}
		for _, line := range strings.Split(string(ipOut), "\n") {
			fields := strings.Fields(line)
			if len(fields) < 4 {
				continue
			}
			name := fields[1]
			if iface, ok := ifaceMap[name]; ok {
				if fields[2] == "inet" && iface.IPv4 == "" {
					addr := fields[3]
					if slashIdx := strings.Index(addr, "/"); slashIdx > 0 {
						addr = addr[:slashIdx]
					}
					iface.IPv4 = addr
				}
			}
		}
	}

	// Link state
	linkOut, err := exec.Command("ip", "-o", "link", "show").Output()
	if err == nil {
		ifaceMap := make(map[string]*NetworkInterface)
		for idx := range m.Interfaces {
			ifaceMap[m.Interfaces[idx].Name] = &m.Interfaces[idx]
		}
		for _, line := range strings.Split(string(linkOut), "\n") {
			if strings.Contains(line, "state UP") {
				fields := strings.Fields(line)
				if len(fields) >= 2 {
					name := strings.TrimSuffix(fields[1], ":")
					if iface, ok := ifaceMap[name]; ok {
						iface.State = "UP"
					}
				}
			} else if strings.Contains(line, "state DOWN") {
				fields := strings.Fields(line)
				if len(fields) >= 2 {
					name := strings.TrimSuffix(fields[1], ":")
					if iface, ok := ifaceMap[name]; ok {
						iface.State = "DOWN"
					}
				}
			}
		}
	}

	// Connection summary from ss
	ssOut, err := exec.Command("ss", "-tunas").Output()
	if err == nil {
		for _, line := range strings.Split(string(ssOut), "\n") {
			fields := strings.Fields(line)
			if len(fields) < 1 {
				continue
			}
			m.Connections.Total++
			state := fields[0]
			switch state {
			case "ESTAB":
				m.Connections.TCPEstablished++
			case "LISTEN":
				if len(fields) >= 5 && strings.HasPrefix(line, "tcp") {
					m.Connections.TCPListening++
				} else {
					m.Connections.UDPListening++
				}
			case "TIME-WAIT":
				m.Connections.TCPTimeWait++
			}
		}
	}

	return m, nil
}
