package metrics

import (
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// DiskMetrics holds filesystem usage information.
type DiskMetrics struct {
	Timestamp   time.Time    `json:"timestamp"`
	Filesystems []Filesystem `json:"filesystems"`
}

// Filesystem represents a single mounted filesystem.
type Filesystem struct {
	Device     string  `json:"device"`
	MountPoint string  `json:"mount_point"`
	FSType     string  `json:"fs_type"`
	TotalBytes uint64  `json:"total_bytes"`
	UsedBytes  uint64  `json:"used_bytes"`
	FreeBytes  uint64  `json:"free_bytes"`
	UsedPct    float64 `json:"used_percent"`
	InodesUsed uint64  `json:"inodes_used"`
	InodesFree uint64  `json:"inodes_free"`
}

// CollectDisk gathers disk/filesystem metrics.
func CollectDisk() (*DiskMetrics, error) {
	m := &DiskMetrics{
		Timestamp: time.Now().UTC(),
	}

	// df output: Filesystem 1K-blocks Used Available Use% Mounted_on
	out, err := exec.Command("df", "-T", "--block-size=1").Output()
	if err != nil {
		return nil, err
	}

	lines := strings.Split(string(out), "\n")
	for i, line := range lines {
		if i == 0 { // skip header
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 7 {
			continue
		}
		// Skip pseudo filesystems
		fsType := fields[1]
		if fsType == "tmpfs" || fsType == "devtmpfs" || fsType == "squashfs" || fsType == "overlay" {
			continue
		}
		device := fields[0]
		if !strings.HasPrefix(device, "/") {
			continue
		}

		total, _ := strconv.ParseUint(fields[2], 10, 64)
		used, _ := strconv.ParseUint(fields[3], 10, 64)
		free, _ := strconv.ParseUint(fields[4], 10, 64)

		pctStr := strings.TrimSuffix(fields[5], "%")
		pct, _ := strconv.ParseFloat(pctStr, 64)

		fs := Filesystem{
			Device:     device,
			MountPoint: fields[6],
			FSType:     fsType,
			TotalBytes: total,
			UsedBytes:  used,
			FreeBytes:  free,
			UsedPct:    pct,
		}

		m.Filesystems = append(m.Filesystems, fs)
	}

	// Inode info
	iout, err := exec.Command("df", "-i").Output()
	if err == nil {
		ilines := strings.Split(string(iout), "\n")
		fsMap := make(map[string]*Filesystem)
		for idx := range m.Filesystems {
			fsMap[m.Filesystems[idx].Device] = &m.Filesystems[idx]
		}
		for i, line := range ilines {
			if i == 0 {
				continue
			}
			fields := strings.Fields(line)
			if len(fields) < 5 {
				continue
			}
			if fs, ok := fsMap[fields[0]]; ok {
				fs.InodesUsed, _ = strconv.ParseUint(fields[2], 10, 64)
				fs.InodesFree, _ = strconv.ParseUint(fields[3], 10, 64)
			}
		}
	}

	return m, nil
}
