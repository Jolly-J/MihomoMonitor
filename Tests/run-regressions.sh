#!/bin/bash
# 用项目真实 Swift 源码编译独立回归程序；不启动 App，也不打开生产数据库。
set -euo pipefail
export TZ=UTC
cd "$(dirname "$0")/.."
TEST_OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/mihomo-regressions.XXXXXX")"
trap 'rm -rf "$TEST_OUTPUT"' EXIT
SOURCE_ROOT="MihomoMonitor/MihomoMonitor"
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  -module-cache-path "$TEST_OUTPUT/modules" -o "$TEST_OUTPUT/regressions" \
  "$SOURCE_ROOT/Features/ProxyTraffic/TrafficModels.swift" \
  "$SOURCE_ROOT/Features/ProxyTraffic/TrafficViewModel.swift" \
  "$SOURCE_ROOT/Persistence/DatabaseManager.swift" \
  "$SOURCE_ROOT/Services/TrafficTracker.swift" \
  "$SOURCE_ROOT/Services/ProcessResolver.swift" \
  "$SOURCE_ROOT/Services/Mihomo/MihomoClient.swift" \
  "$SOURCE_ROOT/Services/Mihomo/MihomoAPIModels.swift" \
  "$SOURCE_ROOT/Services/SystemMetricsCollector.swift" \
  "$SOURCE_ROOT/Features/SystemMonitor/SystemModels.swift" \
  "$SOURCE_ROOT/Features/SystemMonitor/SystemMonitorViewModel.swift" \
  "$SOURCE_ROOT/Shared/MainViewMode.swift" \
  "$SOURCE_ROOT/AppState.swift" Tests/RegressionTests.swift
"$TEST_OUTPUT/regressions"
