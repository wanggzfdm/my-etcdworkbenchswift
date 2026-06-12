# Etcd Workbench Swift MVP

Native macOS SwiftUI rewrite prototype for Etcd Workbench.

## Run

```bash
cd macos-swift
swift run
```

The app stores its local JSON configuration in:

```text
~/Library/Application Support/Etcd Workbench Swift/
```

## Current Scope

Implemented:

- macOS SwiftUI app shell
- Local connection storage
- Connection test through `/version`
- Basic etcd v3 HTTP/JSON gateway calls
- Prefix key listing
- Key create, edit, save, and delete
- Basic username/password auth header
- Basic HTTPS support with optional server verification bypass

Not implemented yet:

- gRPC-native etcd transport
- SSH tunnel
- Client certificate selection
- Lease management
- User and role management
- Key watching
- Snapshot backup
- Batch import/export
- Diff and merge
- Auto update
- Migration from the existing Tauri app configuration

## Notes

This MVP uses etcd's HTTP/JSON gateway endpoints under `/v3/*`. It expects the target etcd server or proxy to accept those requests on the configured host and port.
