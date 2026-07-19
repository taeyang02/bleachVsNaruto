# Online Relay Server

联机对战中继服务器（房间码 + TCP tunnel）。

## 目录（khớp cấu trúc k8s trên server của bạn）

```text
ONLINE_RelayServer/
├── server.js
├── Dockerfile
└── k8s/
    ├── sync-to-home.sh
    └── manifests/base/bvn-online-relay/   # giống ~/k8s/manifests/base/...
        ├── namespace.yaml
        ├── configmap.yaml
        ├── deployment.yaml
        ├── service.yaml
        └── kustomization.yaml
```

Giống pattern sẵn có trên server:

- `~/k8s/manifests/base/kafka/`
- `~/k8s/manifests/base/akhq/`
- `~/k8s/manifests/base/bvn-online-relay/`  ← service này

## Hạ tầng liên quan (từ setup của bạn)

| Thành phần | Ghi chú |
|------------|---------|
| Domain | `*.thaiduongdong.xyz` (Cloudflare) |
| Public IP | `27.72.232.213` |
| Ingress HTTP | Traefik (`traefik-proxy-ingress`) — **không** dùng cho game TCP |
| Expose game | `hostNetwork` + port **17511/tcp** trên node |
| Replicas | **1** (room state in-memory) |

> Cloudflare proxy (cam) **không** forward TCP game. DNS record phải **DNS only** (xám).

## Deploy lên cluster

### 1) Build image trên server / CI

```bash
cd ONLINE_RelayServer
docker build -t bvn-online-relay:1.0.0 .
# nếu dùng containerd/k3s:
# ctr -n k8s.io images import <(docker save bvn-online-relay:1.0.0)
# hoặc đẩy registry rồi sửa image: trong deployment.yaml
```

### 2) Sync manifest về `~/k8s/...` (đúng convention)

```bash
cd ONLINE_RelayServer
chmod +x k8s/sync-to-home.sh
./k8s/sync-to-home.sh
```

### 3) Apply

```bash
kubectl apply -k ~/k8s/manifests/base/bvn-online-relay
kubectl -n bvn-online get pods,svc
kubectl -n bvn-online logs -f deploy/bvn-online-relay
```

### 4) Firewall + DNS

```bash
# mở TCP 17511 trên node
sudo ufw allow 17511/tcp || true

# Cloudflare DNS (DNS only / không proxy):
#   bvn.thaiduongdong.xyz  A  27.72.232.213
```

### 5) Client game `config/online.json`

```json
{
  "host": "bvn.thaiduongdong.xyz",
  "port": 17511,
  "lockKeyframe": 6
}
```

Hoặc dùng thẳng IP `27.72.232.213` nếu chưa tạo DNS.

## Kiểm tra

```bash
# từ máy ngoài
nc -vz bvn.thaiduongdong.xyz 17511
# hoặc
nc -vz 27.72.232.213 17511
```

## Local debug (không qua k8s)

```bash
cd ONLINE_RelayServer
node server.js
```

## Ghi chú Traefik

AKHQ/Jenkins dùng HTTP Ingress + Traefik là đúng.  
Relay BVN là **TCP raw AMF/binary** → **không** gắn `Ingress`/`IngressRoute` HTTP.  
Nếu sau này muốn qua Traefik TCP, cần thêm `entryPoint` + `IngressRouteTCP` riêng; hiện tại `hostNetwork:17511` là cách khớp VPS 1 IP của bạn.
