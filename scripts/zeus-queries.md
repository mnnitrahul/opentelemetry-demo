# Zeus PromQL Query Reference

Datasource: **Zeus** (Prometheus) in AWS Managed Grafana. Use **Code mode**.

## Service Inventory

| Service | Platform | Server Metric | Operations | HTTP Dependencies | RPC Dependencies |
|---------|----------|---------------|------------|-------------------|------------------|
| `ad` | EKS | `rpc.server.duration` | `oteldemo.AdService/GetAds` | — | `flagd/Service` |
| `cart` | EKS | `http.server.request.duration` | `POST /oteldemo.CartService/AddItem`, `POST /oteldemo.CartService/EmptyCart`, `POST /oteldemo.CartService/GetCart` | — | — |
| `checkout` | EKS | `rpc.server.duration` | `oteldemo.CheckoutService/PlaceOrder` | — | `CartService`, `CurrencyService`, `PaymentService`, `ProductCatalogService` |
| `flagd` | EKS | `http.server.request.duration` | `POST /flagd.evaluation.v1.Service/EventStream`, `POST /flagd.evaluation.v1.Service/ResolveAll`, `POST /flagd.evaluation.v1.Service/ResolveBoolean`, `POST /flagd.evaluation.v1.Service/ResolveFloat` +1 | — | — |
| `frontend` | EKS | `http.server.duration` | `GET`, `POST` | `kubernetes` | — |
| `multi-ad` | EKS-multi | `rpc.server.duration` | `oteldemo.AdService/GetAds` | — | `flagd/Service` |
| `multi-checkout` | EKS-multi | `rpc.server.duration` | `oteldemo.CheckoutService/PlaceOrder` | — | `CartService`, `CurrencyService`, `PaymentService`, `ProductCatalogService` |
| `multi-frontend` | EKS-multi | `http.server.duration` | `GET`, `POST` | `kubernetes` | — |
| `multi-inventory-service` | ECS | `http.server.duration` | `GET` | — | — |
| `multi-order-processor` | ECS | `http.server.duration` | `GET`, `POST` | `5qrun1snxd`, `otel-demo-multi-ecs-alb-1127414257` | — |
| `multi-order-processor-java` | ECS | `http.server.request.duration` | `GET /health`, `GET /order-java`, `GET /order-java-slow` | — | — |
| `multi-order-processor-vertx` | ECS | `http.server.request.duration` | `GET /health`, `GET /order-vertx`, `GET /order-vertx-native-db`, `GET /order-vertx-rx-db` +1 | — | — |
| `multi-pricing-service` | ASG | `http.server.duration` | `GET`, `HEAD`, `OPTIONS`, `POST` +1 | — | — |
| `multi-product-catalog` | EKS-multi | `rpc.server.duration` | `oteldemo.ProductCatalogService/GetProduct`, `oteldemo.ProductCatalogService/ListProducts` | — | — |
| `multi-shipping` | EKS-multi | `http.server.duration` | `/get-quote`, `/ship-order` | — | — |
| `product-catalog` | EKS | `rpc.server.duration` | `oteldemo.ProductCatalogService/GetProduct`, `oteldemo.ProductCatalogService/ListProducts` | — | — |
| `shipping` | EKS | `http.server.duration` | `/get-quote`, `/ship-order` | — | — |

## Dependency Operations

| Caller | Dependency | Operations |
|--------|------------|------------|
| `ad` | `flagd/Service` | `EventStream`, `ResolveBoolean` |
| `checkout` | `CartService` | `EmptyCart`, `GetCart` |
| `checkout` | `CurrencyService` | `Convert` |
| `checkout` | `PaymentService` | `Charge` |
| `checkout` | `ProductCatalogService` | `GetProduct` |
| `frontend` | `kubernetes.default.svc` | HTTP calls |
| `multi-ad` | `flagd/Service` | `EventStream`, `ResolveBoolean` |
| `multi-checkout` | `CartService` | `EmptyCart`, `GetCart` |
| `multi-checkout` | `CurrencyService` | `Convert` |
| `multi-checkout` | `PaymentService` | `Charge` |
| `multi-checkout` | `ProductCatalogService` | `GetProduct` |
| `multi-frontend` | `kubernetes.default.svc` | HTTP calls |
| `multi-order-processor` | `5qrun1snxd` | HTTP calls |
| `multi-order-processor` | `otel-demo-multi-ecs-alb-1127414257` | HTTP calls |

---

## Query Templates

Replace `<SVC>`, `<METRIC>`, `<STATUS>`, `<ROUTE_LABEL>`, `<DEP>`, `<DEP_LABEL>` with values from the tables above.

### Variable Reference

| Variable | Old HTTP Semconv | New HTTP Semconv | gRPC |
|----------|-----------------|------------------|------|
| `<METRIC>` | `http.server.duration` | `http.server.request.duration` | `rpc.server.duration` |
| `<CLIENT_METRIC>` | `http.client.duration` | `http.client.duration` | `rpc.client.duration` |
| `<STATUS>` | `http.status_code` | `http.response.status_code` | `rpc.grpc.status_code` |
| `<ROUTE_LABEL>` | `http.route` | `http.route` | `rpc.service`, `rpc.method` |
| `<DEP_LABEL>` | `net.peer.name` | `net.peer.name` | `rpc.service` |

### 1. Service Level

**P99 Latency**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="<METRIC>", "@resource.service.name"="<SVC>"}))
```

**Request Count**
```promql
sum ({__name__="<METRIC>", "@resource.service.name"="<SVC>"})
```

**4xx Count** (HTTP only)
```promql
sum ({__name__="<METRIC>", "@resource.service.name"="<SVC>", "<STATUS>"=~"4.."})
```

**5xx Count** (HTTP only)
```promql
sum ({__name__="<METRIC>", "@resource.service.name"="<SVC>", "<STATUS>"=~"5.."})
```

**Error Count** (gRPC)
```promql
sum ({__name__="rpc.server.duration", "@resource.service.name"="<SVC>", "rpc.grpc.status_code"!="0"})
```

### 2. Service Operation

**P99 Latency by operation** (HTTP)
```promql
histogram_quantile(0.99, sum by ("http.route", le) ({__name__="<METRIC>", "@resource.service.name"="<SVC>"}))
```

**P99 Latency by operation** (gRPC)
```promql
histogram_quantile(0.99, sum by ("rpc.service", "rpc.method", le) ({__name__="rpc.server.duration", "@resource.service.name"="<SVC>"}))
```

**Request Count by operation** (HTTP)
```promql
sum by ("http.route") ({__name__="<METRIC>", "@resource.service.name"="<SVC>"})
```

**Request Count by operation** (gRPC)
```promql
sum by ("rpc.service", "rpc.method") ({__name__="rpc.server.duration", "@resource.service.name"="<SVC>"})
```

**5xx by operation** (HTTP)
```promql
sum by ("http.route") ({__name__="<METRIC>", "@resource.service.name"="<SVC>", "<STATUS>"=~"5.."})
```

**Errors by operation** (gRPC)
```promql
sum by ("rpc.service", "rpc.method") ({__name__="rpc.server.duration", "@resource.service.name"="<SVC>", "rpc.grpc.status_code"!="0"})
```

### 3. Service Dependency

**P99 Latency by dependency** (HTTP)
```promql
histogram_quantile(0.99, sum by ("net.peer.name", le) ({__name__="http.client.duration", "@resource.service.name"="<SVC>"}))
```

**P99 Latency by dependency** (gRPC)
```promql
histogram_quantile(0.99, sum by ("rpc.service", le) ({__name__="rpc.client.duration", "@resource.service.name"="<SVC>"}))
```

**Request Count by dependency** (HTTP)
```promql
sum by ("net.peer.name") ({__name__="http.client.duration", "@resource.service.name"="<SVC>"})
```

**Request Count by dependency** (gRPC)
```promql
sum by ("rpc.service") ({__name__="rpc.client.duration", "@resource.service.name"="<SVC>"})
```

**5xx by dependency** (HTTP)
```promql
sum by ("net.peer.name") ({__name__="http.client.duration", "@resource.service.name"="<SVC>", "http.status_code"=~"5.."})
```

**Errors by dependency** (gRPC)
```promql
sum by ("rpc.service") ({__name__="rpc.client.duration", "@resource.service.name"="<SVC>", "rpc.grpc.status_code"!="0"})
```

### 4. Specific Dependency

**P99 Latency to specific dependency** (HTTP)
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.client.duration", "@resource.service.name"="<SVC>", "net.peer.name"="<DEP>"}))
```

**P99 Latency to specific dependency** (gRPC)
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.client.duration", "@resource.service.name"="<SVC>", "rpc.service"="<DEP>"}))
```

**Request Count to specific dependency**
```promql
sum ({__name__="<CLIENT_METRIC>", "@resource.service.name"="<SVC>", "<DEP_LABEL>"="<DEP>"})
```

**5xx to specific dependency** (HTTP)
```promql
sum ({__name__="http.client.duration", "@resource.service.name"="<SVC>", "net.peer.name"="<DEP>", "http.status_code"=~"5.."})
```

**Errors to specific dependency** (gRPC)
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="<SVC>", "rpc.service"="<DEP>", "rpc.grpc.status_code"!="0"})
```

### 5. Dependency Operation

**P99 Latency by dependency method** (gRPC)
```promql
histogram_quantile(0.99, sum by ("rpc.method", le) ({__name__="rpc.client.duration", "@resource.service.name"="<SVC>", "rpc.service"="<DEP>"}))
```

**Request Count by dependency method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="<SVC>", "rpc.service"="<DEP>"})
```

**Errors by dependency method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="<SVC>", "rpc.service"="<DEP>", "rpc.grpc.status_code"!="0"})
```

### 6. Service Operation → Dependency Operation

Not available from metrics alone. The client-side metrics (`rpc.client.duration`) carry the caller's
service name and the dependency's method, but not the caller's own operation/route. This correlation
requires trace-level data (joining caller span with client span).

---

## Concrete Examples

### `checkout`

**Service p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.server.duration", "@resource.service.name"="checkout"}))
```

**Service count**
```promql
sum ({__name__="rpc.server.duration", "@resource.service.name"="checkout"})
```

**Service errors**
```promql
sum ({__name__="rpc.server.duration", "@resource.service.name"="checkout", "rpc.grpc.status_code"!="0"})
```

**By operation**
```promql
sum by ("rpc.method") ({__name__="rpc.server.duration", "@resource.service.name"="checkout"})
```

**All deps**
```promql
sum by ("rpc.service") ({__name__="rpc.client.duration", "@resource.service.name"="checkout"})
```

**→ ProductCatalog p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.ProductCatalogService"}))
```

**→ ProductCatalog by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.ProductCatalogService"})
```

### `frontend`

**Service p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.server.duration", "@resource.service.name"="frontend"}))
```

**Service 5xx**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="frontend", "http.status_code"=~"5.."})
```

**By route**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="frontend"})
```

**All HTTP deps**
```promql
sum by ("net.peer.name") ({__name__="http.client.duration", "@resource.service.name"="frontend"})
```

### `multi-order-processor`

**Service p99 (ECS)**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.server.duration", "@resource.service.name"="multi-order-processor"}))
```

**Service count**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-order-processor"})
```

**Dep: ECS ALB 5xx**
```promql
sum ({__name__="http.client.duration", "@resource.service.name"="multi-order-processor", "http.status_code"=~"5.."})
```
