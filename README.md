# mojo-health

Kubernetes-compatible health checks for Mojo applications.

## Features

- **HealthChecker** - Aggregate multiple health checks
- **Liveness** - Simple is-alive check
- **Readiness** - Dependency health verification
- **Built-in Probes** - Ping, HTTP, TCP checks
- **Multi-service Aggregator** - Gateway health monitoring

## Installation

```bash
pixi add mojo-health
```

## Quick Start

### Basic Health Checks

```mojo
from mojo_health import HealthChecker, pingCheck

# Create health checker
var health = HealthChecker("gateway", "1.0.0")

# Register checks
health.register(pingCheck("database", db.ping))
health.register(pingCheck("cache", redis.ping))

# Liveness probe (simple is-alive)
var liveness = health.liveness()
# {"status": "healthy", "service": "gateway", "version": "1.0.0"}

# Readiness probe (with dependency checks)
var readiness = health.readiness()
# {"status": "healthy", "checks": [...]}
```

### HTTP Endpoint Check

```mojo
from mojo_health import httpCheck

# Check upstream service health
health.register(httpCheck("auth-service", "http://auth:8080/health"))
health.register(httpCheck("search-service", "http://search:8080/health"))
```

### TCP Connectivity Check

```mojo
from mojo_health import tcpCheck

# Check database connectivity
health.register(tcpCheck("postgres", "postgres:5432"))
health.register(tcpCheck("redis", "redis:6379"))
```

### Custom Check

```mojo
from mojo_health import customCheck, HealthStatus

fn check_disk_space() -> (String, String):
    # Check disk usage
    if get_disk_usage() < 0.9:
        return (HealthStatus.HEALTHY, "Disk OK")
    return (HealthStatus.DEGRADED, "Disk usage > 90%")

health.register(customCheck("disk", check_disk_space))
```

### Multi-Service Aggregation

```mojo
from mojo_health import HealthAggregator

var aggregator = HealthAggregator()
aggregator.register("auth", "http://auth:8080/health")
aggregator.register("search", "http://search:8080/health")
aggregator.register("connector", "http://connector:8080/health")

# Check all services
var status = aggregator.check_all()
# {"overall": "healthy", "healthy": 3, "total": 3, "services": {...}}

# Quick check
if aggregator.is_all_healthy():
    print("All services operational")
```

### Startup Dependency Check

```mojo
from mojo_health import DependencyChecker

var deps = DependencyChecker(timeout_ms=5000, retry_count=10, retry_delay_ms=1000)
deps.add("http://postgres:5432/health")
deps.add("http://redis:6379/health")

# Wait for all dependencies before starting
if deps.wait_for_all():
    start_server()
else:
    print("Dependencies not ready, exiting")
    exit(1)
```

## Kubernetes Integration

### Deployment YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateway
spec:
  template:
    spec:
      containers:
      - name: gateway
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
```

### HTTP Endpoints

```mojo
from mojo_health import HealthChecker

var health = HealthChecker("gateway", "1.0.0")
# ... register checks ...

# In your HTTP handler
fn health_handler() -> Response:
    return json_response(health.liveness())

fn ready_handler() -> Response:
    return json_response(health.readiness())
```

## Check Types

### PingCheck

Calls a function that returns boolean for health status.

```mojo
fn db_ping() -> Bool:
    return database.is_connected()

health.register(pingCheck("database", db_ping))
```

### HttpCheck

Makes HTTP GET request and checks for 2xx response.

```mojo
health.register(httpCheck("upstream", "http://service:8080/health",
    critical=True,
    timeout_ms=3000,
))
```

### TcpCheck

Tests TCP connectivity to host:port.

```mojo
health.register(tcpCheck("redis", "redis:6379",
    critical=False,  # Degraded instead of unhealthy
    timeout_ms=1000,
))
```

## Configuration

### HealthChecker

| Method | Description |
|--------|-------------|
| `register(check)` | Add health check |
| `unregister(name)` | Remove check by name |
| `liveness()` | Simple alive status |
| `readiness()` | Full dependency check |
| `is_ready()` | Boolean readiness |

### Check Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `critical` | true | Failure = unhealthy (vs degraded) |
| `timeout_ms` | 5000 | Check timeout |

## Dependencies

HTTP and TCP checks require Python for network access:

```bash
pip install httpx
```

## Testing

```bash
pixi run test
```

## License

MIT
