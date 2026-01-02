.PHONY: proto clean

# Generate Swift protobuf files
proto:
	@mkdir -p Models/Proto
	protoc --swift_out=Models/Proto \
	       --proto_path=Proto \
	       Proto/snmpproxy.proto
	@echo "Generated Swift protobuf files in Models/Proto/"

clean:
	rm -f Models/Proto/*.pb.swift

# Install swift-protobuf (macOS)
install-tools:
	brew install swift-protobuf

# Verify proto compatibility with server
verify:
	@echo "Checking proto file..."
	@grep -q "GetServerStatusRequest" Proto/snmpproxy.proto && echo "✓ GetServerStatusRequest" || echo "✗ Missing GetServerStatusRequest"
	@grep -q "GetSessionInfoRequest" Proto/snmpproxy.proto && echo "✓ GetSessionInfoRequest" || echo "✗ Missing GetSessionInfoRequest"
	@grep -q "UpdateTargetRequest" Proto/snmpproxy.proto && echo "✓ UpdateTargetRequest" || echo "✗ Missing UpdateTargetRequest"
	@grep -q "GetConfigRequest" Proto/snmpproxy.proto && echo "✓ GetConfigRequest" || echo "✗ Missing GetConfigRequest"
	@grep -q "SetConfigRequest" Proto/snmpproxy.proto && echo "✓ SetConfigRequest" || echo "✗ Missing SetConfigRequest"
	@grep -q "RuntimeConfig" Proto/snmpproxy.proto && echo "✓ RuntimeConfig" || echo "✗ Missing RuntimeConfig"
	@echo "Done."
