# Zeus PromQL Query Reference

All queries use the **Zeus** (Prometheus) datasource in AWS Managed Grafana.
Use **Code mode** in Grafana Explorer. Metric names with dots require `{__name__="..."}` syntax.

## Conventions

| Metric | Semconv | Status Code Label | Route/Method Label |
|--------|---------|-------------------|--------------------|
| `http.server.duration` | old | `http.status_code` | `http.method`, `http.route` |
| `http.server.request.duration` | new | `http.response.status_code` | `http.request.method`, `http.route` |
| `rpc.server.duration` | — | `rpc.grpc.status_code` | `rpc.service`, `rpc.method` |
| `http.client.duration` | old | `http.status_code` | `http.method`, `net.peer.name` |
| `rpc.client.duration` | — | `rpc.grpc.status_code` | `rpc.service`, `rpc.method` |

---

## `ad`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.server.duration", "@resource.service.name"="ad"}))
```

**count**
```promql
sum ({__name__="rpc.server.duration", "@resource.service.name"="ad"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.server.duration", "@resource.service.name"="ad", "rpc.grpc.status_code"!="0"})
```

### Service Operations

RPC operations: `oteldemo.AdService/GetAds`

**p99 by RPC operation**
```promql
histogram_quantile(0.99, sum by ("rpc.service", "rpc.method", le) ({__name__="rpc.server.duration", "@resource.service.name"="ad"}))
```

**count by RPC operation**
```promql
sum by ("rpc.service", "rpc.method") ({__name__="rpc.server.duration", "@resource.service.name"="ad"})
```

**errors (non-OK) by RPC operation**
```promql
sum by ("rpc.service", "rpc.method") ({__name__="rpc.server.duration", "@resource.service.name"="ad", "rpc.grpc.status_code"!="0"})
```

### Service Dependencies

RPC dependencies: `flagd.evaluation.v1.Service`

**p99 by RPC dependency**
```promql
histogram_quantile(0.99, sum by ("rpc.service", le) ({__name__="rpc.client.duration", "@resource.service.name"="ad"}))
```

**count by RPC dependency**
```promql
sum by ("rpc.service") ({__name__="rpc.client.duration", "@resource.service.name"="ad"})
```

**errors (non-OK) by RPC dependency**
```promql
sum by ("rpc.service") ({__name__="rpc.client.duration", "@resource.service.name"="ad", "rpc.grpc.status_code"!="0"})
```

#### → `flagd/Service`

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.client.duration", "@resource.service.name"="ad", "rpc.service"="flagd.evaluation.v1.Service"}))
```

**count**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="ad", "rpc.service"="flagd.evaluation.v1.Service"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="ad", "rpc.service"="flagd.evaluation.v1.Service", "rpc.grpc.status_code"!="0"})
```

**By dependency operation** (`EventStream`, `ResolveBoolean`)

**p99 by method**
```promql
histogram_quantile(0.99, sum by ("rpc.method", le) ({__name__="rpc.client.duration", "@resource.service.name"="ad", "rpc.service"="flagd.evaluation.v1.Service"}))
```

**count by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="ad", "rpc.service"="flagd.evaluation.v1.Service"})
```

**errors (non-OK) by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="ad", "rpc.service"="flagd.evaluation.v1.Service", "rpc.grpc.status_code"!="0"})
```

---

## `cart`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.server.request.duration", "@resource.service.name"="cart"}))
```

**count**
```promql
sum ({__name__="http.server.request.duration", "@resource.service.name"="cart"})
```

**4xx**
```promql
sum ({__name__="http.server.request.duration", "@resource.service.name"="cart", "http.response.status_code"=~"4.."})
```

**5xx**
```promql
sum ({__name__="http.server.request.duration", "@resource.service.name"="cart", "http.response.status_code"=~"5.."})
```

### Service Operations

Operations: `POST /oteldemo.CartService/AddItem`, `POST /oteldemo.CartService/EmptyCart`, `POST /oteldemo.CartService/GetCart`

**p99 by operation**
```promql
histogram_quantile(0.99, sum by ("http.route", le) ({__name__="http.server.request.duration", "@resource.service.name"="cart"}))
```

**count by operation**
```promql
sum by ("http.route") ({__name__="http.server.request.duration", "@resource.service.name"="cart"})
```

**4xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.request.duration", "@resource.service.name"="cart", "http.response.status_code"=~"4.."})
```

**5xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.request.duration", "@resource.service.name"="cart", "http.response.status_code"=~"5.."})
```

---

## `checkout`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.server.duration", "@resource.service.name"="checkout"}))
```

**count**
```promql
sum ({__name__="rpc.server.duration", "@resource.service.name"="checkout"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.server.duration", "@resource.service.name"="checkout", "rpc.grpc.status_code"!="0"})
```

### Service Operations

RPC operations: `oteldemo.CheckoutService/PlaceOrder`

**p99 by RPC operation**
```promql
histogram_quantile(0.99, sum by ("rpc.service", "rpc.method", le) ({__name__="rpc.server.duration", "@resource.service.name"="checkout"}))
```

**count by RPC operation**
```promql
sum by ("rpc.service", "rpc.method") ({__name__="rpc.server.duration", "@resource.service.name"="checkout"})
```

**errors (non-OK) by RPC operation**
```promql
sum by ("rpc.service", "rpc.method") ({__name__="rpc.server.duration", "@resource.service.name"="checkout", "rpc.grpc.status_code"!="0"})
```

### Service Dependencies

RPC dependencies: `oteldemo.CartService`, `oteldemo.CurrencyService`, `oteldemo.PaymentService`, `oteldemo.ProductCatalogService`

**p99 by RPC dependency**
```promql
histogram_quantile(0.99, sum by ("rpc.service", le) ({__name__="rpc.client.duration", "@resource.service.name"="checkout"}))
```

**count by RPC dependency**
```promql
sum by ("rpc.service") ({__name__="rpc.client.duration", "@resource.service.name"="checkout"})
```

**errors (non-OK) by RPC dependency**
```promql
sum by ("rpc.service") ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.grpc.status_code"!="0"})
```

#### → `CartService`

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.CartService"}))
```

**count**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.CartService"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.CartService", "rpc.grpc.status_code"!="0"})
```

**By dependency operation** (`EmptyCart`, `GetCart`)

**p99 by method**
```promql
histogram_quantile(0.99, sum by ("rpc.method", le) ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.CartService"}))
```

**count by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.CartService"})
```

**errors (non-OK) by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.CartService", "rpc.grpc.status_code"!="0"})
```

#### → `CurrencyService`

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.CurrencyService"}))
```

**count**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.CurrencyService"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.CurrencyService", "rpc.grpc.status_code"!="0"})
```

**By dependency operation** (`Convert`)

**p99 by method**
```promql
histogram_quantile(0.99, sum by ("rpc.method", le) ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.CurrencyService"}))
```

**count by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.CurrencyService"})
```

**errors (non-OK) by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.CurrencyService", "rpc.grpc.status_code"!="0"})
```

#### → `PaymentService`

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.PaymentService"}))
```

**count**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.PaymentService"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.PaymentService", "rpc.grpc.status_code"!="0"})
```

**By dependency operation** (`Charge`)

**p99 by method**
```promql
histogram_quantile(0.99, sum by ("rpc.method", le) ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.PaymentService"}))
```

**count by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.PaymentService"})
```

**errors (non-OK) by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.PaymentService", "rpc.grpc.status_code"!="0"})
```

#### → `ProductCatalogService`

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.ProductCatalogService"}))
```

**count**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.ProductCatalogService"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.ProductCatalogService", "rpc.grpc.status_code"!="0"})
```

**By dependency operation** (`GetProduct`)

**p99 by method**
```promql
histogram_quantile(0.99, sum by ("rpc.method", le) ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.ProductCatalogService"}))
```

**count by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.ProductCatalogService"})
```

**errors (non-OK) by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="checkout", "rpc.service"="oteldemo.ProductCatalogService", "rpc.grpc.status_code"!="0"})
```

---

## `flagd`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.server.request.duration", "@resource.service.name"="flagd"}))
```

**count**
```promql
sum ({__name__="http.server.request.duration", "@resource.service.name"="flagd"})
```

**4xx**
```promql
sum ({__name__="http.server.request.duration", "@resource.service.name"="flagd", "http.response.status_code"=~"4.."})
```

**5xx**
```promql
sum ({__name__="http.server.request.duration", "@resource.service.name"="flagd", "http.response.status_code"=~"5.."})
```

### Service Operations

Operations: `POST /flagd.evaluation.v1.Service/EventStream`, `POST /flagd.evaluation.v1.Service/ResolveAll`, `POST /flagd.evaluation.v1.Service/ResolveBoolean`, `POST /flagd.evaluation.v1.Service/ResolveFloat`, `POST /flagd.evaluation.v1.Service/ResolveInt`

**p99 by operation**
```promql
histogram_quantile(0.99, sum by ("http.route", le) ({__name__="http.server.request.duration", "@resource.service.name"="flagd"}))
```

**count by operation**
```promql
sum by ("http.route") ({__name__="http.server.request.duration", "@resource.service.name"="flagd"})
```

**4xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.request.duration", "@resource.service.name"="flagd", "http.response.status_code"=~"4.."})
```

**5xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.request.duration", "@resource.service.name"="flagd", "http.response.status_code"=~"5.."})
```

---

## `frontend`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.server.duration", "@resource.service.name"="frontend"}))
```

**count**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="frontend"})
```

**4xx**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="frontend", "http.status_code"=~"4.."})
```

**5xx**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="frontend", "http.status_code"=~"5.."})
```

### Service Operations

Operations: `GET unknown`, `POST unknown`

**p99 by operation**
```promql
histogram_quantile(0.99, sum by ("http.route", le) ({__name__="http.server.duration", "@resource.service.name"="frontend"}))
```

**count by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="frontend"})
```

**4xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="frontend", "http.status_code"=~"4.."})
```

**5xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="frontend", "http.status_code"=~"5.."})
```

### Service Dependencies

HTTP dependencies: `kubernetes.default.svc`

**p99 by dependency**
```promql
histogram_quantile(0.99, sum by ("net.peer.name", le) ({__name__="http.client.duration", "@resource.service.name"="frontend"}))
```

**count by dependency**
```promql
sum by ("net.peer.name") ({__name__="http.client.duration", "@resource.service.name"="frontend"})
```

**4xx by dependency**
```promql
sum by ("net.peer.name") ({__name__="http.client.duration", "@resource.service.name"="frontend", "http.status_code"=~"4.."})
```

**5xx by dependency**
```promql
sum by ("net.peer.name") ({__name__="http.client.duration", "@resource.service.name"="frontend", "http.status_code"=~"5.."})
```

#### → `kubernetes.default.svc`

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.client.duration", "@resource.service.name"="frontend", "net.peer.name"="kubernetes.default.svc"}))
```

**count**
```promql
sum ({__name__="http.client.duration", "@resource.service.name"="frontend", "net.peer.name"="kubernetes.default.svc"})
```

**4xx**
```promql
sum ({__name__="http.client.duration", "@resource.service.name"="frontend", "net.peer.name"="kubernetes.default.svc", "http.status_code"=~"4.."})
```

**5xx**
```promql
sum ({__name__="http.client.duration", "@resource.service.name"="frontend", "net.peer.name"="kubernetes.default.svc", "http.status_code"=~"5.."})
```

---

## `multi-ad`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.server.duration", "@resource.service.name"="multi-ad"}))
```

**count**
```promql
sum ({__name__="rpc.server.duration", "@resource.service.name"="multi-ad"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.server.duration", "@resource.service.name"="multi-ad", "rpc.grpc.status_code"!="0"})
```

### Service Operations

RPC operations: `oteldemo.AdService/GetAds`

**p99 by RPC operation**
```promql
histogram_quantile(0.99, sum by ("rpc.service", "rpc.method", le) ({__name__="rpc.server.duration", "@resource.service.name"="multi-ad"}))
```

**count by RPC operation**
```promql
sum by ("rpc.service", "rpc.method") ({__name__="rpc.server.duration", "@resource.service.name"="multi-ad"})
```

**errors (non-OK) by RPC operation**
```promql
sum by ("rpc.service", "rpc.method") ({__name__="rpc.server.duration", "@resource.service.name"="multi-ad", "rpc.grpc.status_code"!="0"})
```

### Service Dependencies

RPC dependencies: `flagd.evaluation.v1.Service`

**p99 by RPC dependency**
```promql
histogram_quantile(0.99, sum by ("rpc.service", le) ({__name__="rpc.client.duration", "@resource.service.name"="multi-ad"}))
```

**count by RPC dependency**
```promql
sum by ("rpc.service") ({__name__="rpc.client.duration", "@resource.service.name"="multi-ad"})
```

**errors (non-OK) by RPC dependency**
```promql
sum by ("rpc.service") ({__name__="rpc.client.duration", "@resource.service.name"="multi-ad", "rpc.grpc.status_code"!="0"})
```

#### → `flagd/Service`

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.client.duration", "@resource.service.name"="multi-ad", "rpc.service"="flagd.evaluation.v1.Service"}))
```

**count**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="multi-ad", "rpc.service"="flagd.evaluation.v1.Service"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="multi-ad", "rpc.service"="flagd.evaluation.v1.Service", "rpc.grpc.status_code"!="0"})
```

**By dependency operation** (`EventStream`, `ResolveBoolean`)

**p99 by method**
```promql
histogram_quantile(0.99, sum by ("rpc.method", le) ({__name__="rpc.client.duration", "@resource.service.name"="multi-ad", "rpc.service"="flagd.evaluation.v1.Service"}))
```

**count by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="multi-ad", "rpc.service"="flagd.evaluation.v1.Service"})
```

**errors (non-OK) by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="multi-ad", "rpc.service"="flagd.evaluation.v1.Service", "rpc.grpc.status_code"!="0"})
```

---

## `multi-checkout`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.server.duration", "@resource.service.name"="multi-checkout"}))
```

**count**
```promql
sum ({__name__="rpc.server.duration", "@resource.service.name"="multi-checkout"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.server.duration", "@resource.service.name"="multi-checkout", "rpc.grpc.status_code"!="0"})
```

### Service Operations

RPC operations: `oteldemo.CheckoutService/PlaceOrder`

**p99 by RPC operation**
```promql
histogram_quantile(0.99, sum by ("rpc.service", "rpc.method", le) ({__name__="rpc.server.duration", "@resource.service.name"="multi-checkout"}))
```

**count by RPC operation**
```promql
sum by ("rpc.service", "rpc.method") ({__name__="rpc.server.duration", "@resource.service.name"="multi-checkout"})
```

**errors (non-OK) by RPC operation**
```promql
sum by ("rpc.service", "rpc.method") ({__name__="rpc.server.duration", "@resource.service.name"="multi-checkout", "rpc.grpc.status_code"!="0"})
```

### Service Dependencies

RPC dependencies: `oteldemo.CartService`, `oteldemo.CurrencyService`, `oteldemo.PaymentService`, `oteldemo.ProductCatalogService`

**p99 by RPC dependency**
```promql
histogram_quantile(0.99, sum by ("rpc.service", le) ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout"}))
```

**count by RPC dependency**
```promql
sum by ("rpc.service") ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout"})
```

**errors (non-OK) by RPC dependency**
```promql
sum by ("rpc.service") ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.grpc.status_code"!="0"})
```

#### → `CartService`

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.CartService"}))
```

**count**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.CartService"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.CartService", "rpc.grpc.status_code"!="0"})
```

**By dependency operation** (`EmptyCart`, `GetCart`)

**p99 by method**
```promql
histogram_quantile(0.99, sum by ("rpc.method", le) ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.CartService"}))
```

**count by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.CartService"})
```

**errors (non-OK) by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.CartService", "rpc.grpc.status_code"!="0"})
```

#### → `CurrencyService`

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.CurrencyService"}))
```

**count**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.CurrencyService"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.CurrencyService", "rpc.grpc.status_code"!="0"})
```

**By dependency operation** (`Convert`)

**p99 by method**
```promql
histogram_quantile(0.99, sum by ("rpc.method", le) ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.CurrencyService"}))
```

**count by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.CurrencyService"})
```

**errors (non-OK) by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.CurrencyService", "rpc.grpc.status_code"!="0"})
```

#### → `PaymentService`

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.PaymentService"}))
```

**count**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.PaymentService"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.PaymentService", "rpc.grpc.status_code"!="0"})
```

**By dependency operation** (`Charge`)

**p99 by method**
```promql
histogram_quantile(0.99, sum by ("rpc.method", le) ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.PaymentService"}))
```

**count by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.PaymentService"})
```

**errors (non-OK) by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.PaymentService", "rpc.grpc.status_code"!="0"})
```

#### → `ProductCatalogService`

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.ProductCatalogService"}))
```

**count**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.ProductCatalogService"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.ProductCatalogService", "rpc.grpc.status_code"!="0"})
```

**By dependency operation** (`GetProduct`)

**p99 by method**
```promql
histogram_quantile(0.99, sum by ("rpc.method", le) ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.ProductCatalogService"}))
```

**count by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.ProductCatalogService"})
```

**errors (non-OK) by method**
```promql
sum by ("rpc.method") ({__name__="rpc.client.duration", "@resource.service.name"="multi-checkout", "rpc.service"="oteldemo.ProductCatalogService", "rpc.grpc.status_code"!="0"})
```

---

## `multi-frontend`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.server.duration", "@resource.service.name"="multi-frontend"}))
```

**count**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-frontend"})
```

**4xx**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-frontend", "http.status_code"=~"4.."})
```

**5xx**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-frontend", "http.status_code"=~"5.."})
```

### Service Operations

Operations: `GET unknown`, `POST unknown`

**p99 by operation**
```promql
histogram_quantile(0.99, sum by ("http.route", le) ({__name__="http.server.duration", "@resource.service.name"="multi-frontend"}))
```

**count by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="multi-frontend"})
```

**4xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="multi-frontend", "http.status_code"=~"4.."})
```

**5xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="multi-frontend", "http.status_code"=~"5.."})
```

### Service Dependencies

HTTP dependencies: `kubernetes.default.svc`

**p99 by dependency**
```promql
histogram_quantile(0.99, sum by ("net.peer.name", le) ({__name__="http.client.duration", "@resource.service.name"="multi-frontend"}))
```

**count by dependency**
```promql
sum by ("net.peer.name") ({__name__="http.client.duration", "@resource.service.name"="multi-frontend"})
```

**4xx by dependency**
```promql
sum by ("net.peer.name") ({__name__="http.client.duration", "@resource.service.name"="multi-frontend", "http.status_code"=~"4.."})
```

**5xx by dependency**
```promql
sum by ("net.peer.name") ({__name__="http.client.duration", "@resource.service.name"="multi-frontend", "http.status_code"=~"5.."})
```

#### → `kubernetes.default.svc`

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.client.duration", "@resource.service.name"="multi-frontend", "net.peer.name"="kubernetes.default.svc"}))
```

**count**
```promql
sum ({__name__="http.client.duration", "@resource.service.name"="multi-frontend", "net.peer.name"="kubernetes.default.svc"})
```

**4xx**
```promql
sum ({__name__="http.client.duration", "@resource.service.name"="multi-frontend", "net.peer.name"="kubernetes.default.svc", "http.status_code"=~"4.."})
```

**5xx**
```promql
sum ({__name__="http.client.duration", "@resource.service.name"="multi-frontend", "net.peer.name"="kubernetes.default.svc", "http.status_code"=~"5.."})
```

---

## `multi-inventory-service`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.server.duration", "@resource.service.name"="multi-inventory-service"}))
```

**count**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-inventory-service"})
```

**4xx**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-inventory-service", "http.status_code"=~"4.."})
```

**5xx**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-inventory-service", "http.status_code"=~"5.."})
```

### Service Operations

Operations: `GET unknown`

**p99 by operation**
```promql
histogram_quantile(0.99, sum by ("http.route", le) ({__name__="http.server.duration", "@resource.service.name"="multi-inventory-service"}))
```

**count by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="multi-inventory-service"})
```

**4xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="multi-inventory-service", "http.status_code"=~"4.."})
```

**5xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="multi-inventory-service", "http.status_code"=~"5.."})
```

---

## `multi-order-processor`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.server.duration", "@resource.service.name"="multi-order-processor"}))
```

**count**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-order-processor"})
```

**4xx**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-order-processor", "http.status_code"=~"4.."})
```

**5xx**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-order-processor", "http.status_code"=~"5.."})
```

### Service Operations

Operations: `GET unknown`, `POST unknown`

**p99 by operation**
```promql
histogram_quantile(0.99, sum by ("http.route", le) ({__name__="http.server.duration", "@resource.service.name"="multi-order-processor"}))
```

**count by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="multi-order-processor"})
```

**4xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="multi-order-processor", "http.status_code"=~"4.."})
```

**5xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="multi-order-processor", "http.status_code"=~"5.."})
```

### Service Dependencies

HTTP dependencies: `5qrun1snxd.execute-api.us-east-1.amazonaws.com`, `otel-demo-multi-ecs-alb-1127414257.us-east-1.elb.amazonaws.com`

**p99 by dependency**
```promql
histogram_quantile(0.99, sum by ("net.peer.name", le) ({__name__="http.client.duration", "@resource.service.name"="multi-order-processor"}))
```

**count by dependency**
```promql
sum by ("net.peer.name") ({__name__="http.client.duration", "@resource.service.name"="multi-order-processor"})
```

**4xx by dependency**
```promql
sum by ("net.peer.name") ({__name__="http.client.duration", "@resource.service.name"="multi-order-processor", "http.status_code"=~"4.."})
```

**5xx by dependency**
```promql
sum by ("net.peer.name") ({__name__="http.client.duration", "@resource.service.name"="multi-order-processor", "http.status_code"=~"5.."})
```

#### → `5qrun1snxd.execute-api.us-east-1.amazonaws.com`

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.client.duration", "@resource.service.name"="multi-order-processor", "net.peer.name"="5qrun1snxd.execute-api.us-east-1.amazonaws.com"}))
```

**count**
```promql
sum ({__name__="http.client.duration", "@resource.service.name"="multi-order-processor", "net.peer.name"="5qrun1snxd.execute-api.us-east-1.amazonaws.com"})
```

**4xx**
```promql
sum ({__name__="http.client.duration", "@resource.service.name"="multi-order-processor", "net.peer.name"="5qrun1snxd.execute-api.us-east-1.amazonaws.com", "http.status_code"=~"4.."})
```

**5xx**
```promql
sum ({__name__="http.client.duration", "@resource.service.name"="multi-order-processor", "net.peer.name"="5qrun1snxd.execute-api.us-east-1.amazonaws.com", "http.status_code"=~"5.."})
```

#### → `otel-demo-multi-ecs-alb-1127414257.us-east-1.elb.amazonaws.com`

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.client.duration", "@resource.service.name"="multi-order-processor", "net.peer.name"="otel-demo-multi-ecs-alb-1127414257.us-east-1.elb.amazonaws.com"}))
```

**count**
```promql
sum ({__name__="http.client.duration", "@resource.service.name"="multi-order-processor", "net.peer.name"="otel-demo-multi-ecs-alb-1127414257.us-east-1.elb.amazonaws.com"})
```

**4xx**
```promql
sum ({__name__="http.client.duration", "@resource.service.name"="multi-order-processor", "net.peer.name"="otel-demo-multi-ecs-alb-1127414257.us-east-1.elb.amazonaws.com", "http.status_code"=~"4.."})
```

**5xx**
```promql
sum ({__name__="http.client.duration", "@resource.service.name"="multi-order-processor", "net.peer.name"="otel-demo-multi-ecs-alb-1127414257.us-east-1.elb.amazonaws.com", "http.status_code"=~"5.."})
```

---

## `multi-order-processor-java`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-java"}))
```

**count**
```promql
sum ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-java"})
```

**4xx**
```promql
sum ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-java", "http.response.status_code"=~"4.."})
```

**5xx**
```promql
sum ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-java", "http.response.status_code"=~"5.."})
```

### Service Operations

Operations: `GET /health`, `GET /order-java`, `GET /order-java-slow`

**p99 by operation**
```promql
histogram_quantile(0.99, sum by ("http.route", le) ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-java"}))
```

**count by operation**
```promql
sum by ("http.route") ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-java"})
```

**4xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-java", "http.response.status_code"=~"4.."})
```

**5xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-java", "http.response.status_code"=~"5.."})
```

---

## `multi-order-processor-vertx`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-vertx"}))
```

**count**
```promql
sum ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-vertx"})
```

**4xx**
```promql
sum ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-vertx", "http.response.status_code"=~"4.."})
```

**5xx**
```promql
sum ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-vertx", "http.response.status_code"=~"5.."})
```

### Service Operations

Operations: `GET /health`, `GET /order-vertx`, `GET /order-vertx-native-db`, `GET /order-vertx-rx-db`, `GET /order-vertx-slow`

**p99 by operation**
```promql
histogram_quantile(0.99, sum by ("http.route", le) ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-vertx"}))
```

**count by operation**
```promql
sum by ("http.route") ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-vertx"})
```

**4xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-vertx", "http.response.status_code"=~"4.."})
```

**5xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.request.duration", "@resource.service.name"="multi-order-processor-vertx", "http.response.status_code"=~"5.."})
```

---

## `multi-pricing-service`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.server.duration", "@resource.service.name"="multi-pricing-service"}))
```

**count**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-pricing-service"})
```

**4xx**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-pricing-service", "http.status_code"=~"4.."})
```

**5xx**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-pricing-service", "http.status_code"=~"5.."})
```

### Service Operations

Operations: `GET unknown`, `HEAD unknown`, `OPTIONS unknown`, `POST unknown`, `_OTHER unknown`

**p99 by operation**
```promql
histogram_quantile(0.99, sum by ("http.route", le) ({__name__="http.server.duration", "@resource.service.name"="multi-pricing-service"}))
```

**count by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="multi-pricing-service"})
```

**4xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="multi-pricing-service", "http.status_code"=~"4.."})
```

**5xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="multi-pricing-service", "http.status_code"=~"5.."})
```

---

## `multi-product-catalog`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.server.duration", "@resource.service.name"="multi-product-catalog"}))
```

**count**
```promql
sum ({__name__="rpc.server.duration", "@resource.service.name"="multi-product-catalog"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.server.duration", "@resource.service.name"="multi-product-catalog", "rpc.grpc.status_code"!="0"})
```

### Service Operations

RPC operations: `oteldemo.ProductCatalogService/GetProduct`, `oteldemo.ProductCatalogService/ListProducts`

**p99 by RPC operation**
```promql
histogram_quantile(0.99, sum by ("rpc.service", "rpc.method", le) ({__name__="rpc.server.duration", "@resource.service.name"="multi-product-catalog"}))
```

**count by RPC operation**
```promql
sum by ("rpc.service", "rpc.method") ({__name__="rpc.server.duration", "@resource.service.name"="multi-product-catalog"})
```

**errors (non-OK) by RPC operation**
```promql
sum by ("rpc.service", "rpc.method") ({__name__="rpc.server.duration", "@resource.service.name"="multi-product-catalog", "rpc.grpc.status_code"!="0"})
```

---

## `multi-shipping`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.server.duration", "@resource.service.name"="multi-shipping"}))
```

**count**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-shipping"})
```

**4xx**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-shipping", "http.status_code"=~"4.."})
```

**5xx**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="multi-shipping", "http.status_code"=~"5.."})
```

### Service Operations

Operations: ` /get-quote`, ` /ship-order`

**p99 by operation**
```promql
histogram_quantile(0.99, sum by ("http.route", le) ({__name__="http.server.duration", "@resource.service.name"="multi-shipping"}))
```

**count by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="multi-shipping"})
```

**4xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="multi-shipping", "http.status_code"=~"4.."})
```

**5xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="multi-shipping", "http.status_code"=~"5.."})
```

---

## `product-catalog`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="rpc.server.duration", "@resource.service.name"="product-catalog"}))
```

**count**
```promql
sum ({__name__="rpc.server.duration", "@resource.service.name"="product-catalog"})
```

**errors (non-OK)**
```promql
sum ({__name__="rpc.server.duration", "@resource.service.name"="product-catalog", "rpc.grpc.status_code"!="0"})
```

### Service Operations

RPC operations: `oteldemo.ProductCatalogService/GetProduct`, `oteldemo.ProductCatalogService/ListProducts`

**p99 by RPC operation**
```promql
histogram_quantile(0.99, sum by ("rpc.service", "rpc.method", le) ({__name__="rpc.server.duration", "@resource.service.name"="product-catalog"}))
```

**count by RPC operation**
```promql
sum by ("rpc.service", "rpc.method") ({__name__="rpc.server.duration", "@resource.service.name"="product-catalog"})
```

**errors (non-OK) by RPC operation**
```promql
sum by ("rpc.service", "rpc.method") ({__name__="rpc.server.duration", "@resource.service.name"="product-catalog", "rpc.grpc.status_code"!="0"})
```

---

## `shipping`

### Service Level

**p99**
```promql
histogram_quantile(0.99, sum by (le) ({__name__="http.server.duration", "@resource.service.name"="shipping"}))
```

**count**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="shipping"})
```

**4xx**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="shipping", "http.status_code"=~"4.."})
```

**5xx**
```promql
sum ({__name__="http.server.duration", "@resource.service.name"="shipping", "http.status_code"=~"5.."})
```

### Service Operations

Operations: ` /get-quote`, ` /ship-order`

**p99 by operation**
```promql
histogram_quantile(0.99, sum by ("http.route", le) ({__name__="http.server.duration", "@resource.service.name"="shipping"}))
```

**count by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="shipping"})
```

**4xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="shipping", "http.status_code"=~"4.."})
```

**5xx by operation**
```promql
sum by ("http.route") ({__name__="http.server.duration", "@resource.service.name"="shipping", "http.status_code"=~"5.."})
```

---