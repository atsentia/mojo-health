"""
Example: Kubernetes Health Checks

Demonstrates:
- Liveness probe (is the service alive?)
- Readiness probe (is the service ready for traffic?)
- Custom health checks
- Health aggregation
"""

from mojo_health import HealthChecker, CheckResult, HealthStatus
from mojo_health import pingCheck, httpCheck, tcpCheck
from mojo_health import HealthAggregator, ServiceHealth


fn basic_health_check():
    """Basic liveness and readiness."""
    print("=== Basic Health Checks ===")

    # Create health checker
    var health = HealthChecker("api-gateway", "1.0.0")

    # Liveness probe - always returns OK if service is running
    var liveness = health.liveness()
    print("GET /health/live")
    print('{"status": "UP", "service": "api-gateway", "version": "1.0.0"}')

    # Readiness probe - checks dependencies
    var readiness = health.readiness()
    print("\nGET /health/ready")
    print('{"status": "UP", "checks": [...]}')
    print("")


fn dependency_checks() raises:
    """Check external dependencies."""
    print("=== Dependency Checks ===")

    var health = HealthChecker("order-service", "2.0.0")

    # Register checks for dependencies
    fn database_ping() raises -> Bool:
        # Simulated DB ping
        return True

    fn redis_ping() raises -> Bool:
        # Simulated Redis ping
        return True

    fn kafka_ping() raises -> Bool:
        # Simulated Kafka ping
        return False  # Simulating failure

    health.register(pingCheck("database", database_ping))
    health.register(pingCheck("redis", redis_ping))
    health.register(pingCheck("kafka", kafka_ping))

    # Run readiness check
    var result = health.readiness()

    print("Readiness check results:")
    print("  database: UP")
    print("  redis: UP")
    print("  kafka: DOWN")
    print("  overall: DOWN (one or more checks failed)")
    print("")


fn custom_checks():
    """Create custom health checks."""
    print("=== Custom Health Checks ===")

    var health = HealthChecker("analytics-service", "1.5.0")

    # Memory check
    fn check_memory() raises -> CheckResult:
        var used_mb = 512  # Simulated
        var max_mb = 1024
        if used_mb > max_mb * 0.9:
            return CheckResult.down("Memory usage critical: " + String(used_mb) + "MB")
        return CheckResult.up("Memory OK: " + String(used_mb) + "/" + String(max_mb) + "MB")

    # Disk check
    fn check_disk() raises -> CheckResult:
        var used_pct = 75  # Simulated
        if used_pct > 90:
            return CheckResult.down("Disk usage critical: " + String(used_pct) + "%")
        return CheckResult.up("Disk OK: " + String(used_pct) + "% used")

    # Queue depth check
    fn check_queue() raises -> CheckResult:
        var depth = 150  # Simulated
        if depth > 1000:
            return CheckResult.degraded("Queue backing up: " + String(depth))
        return CheckResult.up("Queue OK: " + String(depth) + " items")

    health.register_custom("memory", check_memory)
    health.register_custom("disk", check_disk)
    health.register_custom("queue", check_queue)

    print("Custom checks registered: memory, disk, queue")
    print("GET /health/ready returns all check statuses")
    print("")


fn aggregated_health():
    """Aggregate health from multiple services."""
    print("=== Health Aggregation ===")

    var aggregator = HealthAggregator()

    # Register services
    aggregator.register("api-gateway", "http://gateway:8080/health")
    aggregator.register("order-service", "http://orders:8080/health")
    aggregator.register("user-service", "http://users:8080/health")

    # Get aggregated health
    var health = aggregator.check_all()

    print("Aggregated health status:")
    print("  api-gateway: UP")
    print("  order-service: UP")
    print("  user-service: DOWN")
    print("  overall: DEGRADED")
    print("")


fn kubernetes_integration():
    """Kubernetes probe configuration."""
    print("=== Kubernetes Integration ===")

    print("Pod spec configuration:")
    print("""
spec:
  containers:
  - name: api
    livenessProbe:
      httpGet:
        path: /health/live
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 10
    readinessProbe:
      httpGet:
        path: /health/ready
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 5
      failureThreshold: 3
""")


fn main() raises:
    print("mojo-health: Kubernetes Health Checks\n")

    basic_health_check()
    dependency_checks()
    custom_checks()
    aggregated_health()
    kubernetes_integration()

    print("=" * 50)
    print("Endpoints:")
    print("  /health/live  - Liveness (is service running?)")
    print("  /health/ready - Readiness (is service ready?)")
    print("  /health       - Full health details")
