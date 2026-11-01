#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/tests
swiftc Sources/shared/ControlModel.swift Tests/ControlPolicyTests.swift -o work/tests/policy-tests
work/tests/policy-tests
swiftc Sources/shared/*.swift Tests/PreviewControlTests.swift -o work/tests/preview-tests
work/tests/preview-tests
python3 Tests/preview_control_integration.py
swiftc Sources/shared/*.swift Sources/daemon/*.swift -o work/tests/macmini-moded
swiftc Sources/shared/*.swift Sources/control/*.swift -o work/tests/macminimode-control
python3 Tests/socket_deadline_integration.py
python3 Tests/control_integration.py
