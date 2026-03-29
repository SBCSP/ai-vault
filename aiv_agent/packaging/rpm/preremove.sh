#!/bin/bash
systemctl stop aiv_agent.service 2>/dev/null || true
systemctl disable aiv_agent.service 2>/dev/null || true
