package metrics

import (
	"os/exec"
	"strings"
	"time"
)

// ServiceMetrics holds systemd service status information.
type ServiceMetrics struct {
	Timestamp time.Time       `json:"timestamp"`
	Services  []ServiceStatus `json:"services"`
}

// ServiceStatus represents the state of a systemd service.
type ServiceStatus struct {
	Name        string `json:"name"`
	LoadState   string `json:"load_state"`
	ActiveState string `json:"active_state"`
	SubState    string `json:"sub_state"`
	Description string `json:"description"`
}

// CollectServices gathers systemd service statuses.
func CollectServices() (*ServiceMetrics, error) {
	m := &ServiceMetrics{
		Timestamp: time.Now().UTC(),
	}

	// List all loaded services
	out, err := exec.Command("systemctl", "list-units", "--type=service", "--no-pager", "--no-legend", "--plain").Output()
	if err != nil {
		return nil, err
	}

	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		// Format: UNIT LOAD ACTIVE SUB DESCRIPTION...
		fields := strings.Fields(line)
		if len(fields) < 5 {
			continue
		}

		svc := ServiceStatus{
			Name:        strings.TrimSuffix(fields[0], ".service"),
			LoadState:   fields[1],
			ActiveState: fields[2],
			SubState:    fields[3],
			Description: strings.Join(fields[4:], " "),
		}
		m.Services = append(m.Services, svc)
	}

	return m, nil
}
