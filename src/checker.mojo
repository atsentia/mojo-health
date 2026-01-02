"""
Health Checker Framework

Provides health check aggregation for Kubernetes probes:
- Liveness: Is the process alive?
- Readiness: Are dependencies healthy?

Example:
    var health = HealthChecker("gateway", "1.0.0")
    health.register(DatabaseCheck(db_url))
    health.register(RedisCheck(redis_url))

    # Simple liveness
    var liveness = health.liveness()
    # {"status": "healthy", "service": "gateway", "version": "1.0.0"}

    # Full readiness with checks
    var readiness = health.readiness()
    # {"status": "healthy", "checks": [...]}
"""

from time import perf_counter_ns


struct HealthStatus:
    """Health status constants."""

    alias HEALTHY: String = "healthy"
    alias UNHEALTHY: String = "unhealthy"
    alias DEGRADED: String = "degraded"

    @staticmethod
    fn is_healthy(status: String) -> Bool:
        return status == HealthStatus.HEALTHY

    @staticmethod
    fn is_degraded(status: String) -> Bool:
        return status == HealthStatus.DEGRADED

    @staticmethod
    fn is_unhealthy(status: String) -> Bool:
        return status == HealthStatus.UNHEALTHY


@value
struct CheckResult:
    """Result of a single health check."""

    var name: String
    """Check name."""

    var status: String
    """Health status (healthy/unhealthy/degraded)."""

    var message: String
    """Optional status message."""

    var latency_ms: Float64
    """Check latency in milliseconds."""

    var timestamp_ns: Int
    """Check timestamp in nanoseconds."""

    fn __init__(out self, name: String, status: String):
        """Create result with status."""
        self.name = name
        self.status = status
        self.message = ""
        self.latency_ms = 0.0
        self.timestamp_ns = perf_counter_ns()

    fn __init__(
        inout self,
        name: String,
        status: String,
        message: String,
        latency_ms: Float64 = 0.0,
    ):
        """Create result with all fields."""
        self.name = name
        self.status = status
        self.message = message
        self.latency_ms = latency_ms
        self.timestamp_ns = perf_counter_ns()

    fn is_healthy(self) -> Bool:
        """Check if result is healthy."""
        return self.status == HealthStatus.HEALTHY

    fn to_dict(self) -> Dict[String, String]:
        """Convert to dictionary."""
        var d = Dict[String, String]()
        d["name"] = self.name
        d["status"] = self.status
        if len(self.message) > 0:
            d["message"] = self.message
        d["latency_ms"] = str(self.latency_ms)
        return d


trait HealthCheck:
    """Trait for implementing health checks."""

    fn name(self) -> String:
        """Get check name."""
        ...

    fn check(self) -> CheckResult:
        """Run the health check."""
        ...

    fn is_critical(self) -> Bool:
        """Whether failure should make service unhealthy (vs degraded)."""
        ...


struct HealthChecker:
    """
    Health check aggregator.

    Registers multiple health checks and aggregates their status.
    Provides Kubernetes-compatible liveness and readiness endpoints.
    """

    var service_name: String
    """Service name for identification."""

    var version: String
    """Service version."""

    var checks: List[HealthCheck]
    """Registered health checks."""

    var last_check_time_ns: Int
    """Timestamp of last readiness check."""

    fn __init__(out self, service_name: String, version: String):
        """Create health checker for service."""
        self.service_name = service_name
        self.version = version
        self.checks = List[HealthCheck]()
        self.last_check_time_ns = 0

    fn register(inout self, check: HealthCheck):
        """Register a health check."""
        self.checks.append(check)

    fn unregister(inout self, name: String):
        """Unregister a health check by name."""
        var new_checks = List[HealthCheck]()
        for check in self.checks:
            if check.name() != name:
                new_checks.append(check)
        self.checks = new_checks

    fn liveness(self) -> Dict[String, String]:
        """
        Simple liveness check.

        Returns basic service info without running checks.
        Use for Kubernetes liveness probe.
        """
        var result = Dict[String, String]()
        result["status"] = HealthStatus.HEALTHY
        result["service"] = self.service_name
        result["version"] = self.version
        return result

    fn readiness(inout self) -> Dict[String, Any]:
        """
        Full readiness check.

        Runs all registered checks and aggregates status.
        Use for Kubernetes readiness probe.
        """
        self.last_check_time_ns = perf_counter_ns()

        var results = List[CheckResult]()
        var overall = HealthStatus.HEALTHY
        var has_critical_failure = False

        # Run all checks
        for check in self.checks:
            var start_ns = perf_counter_ns()
            var result = check.check()
            result.latency_ms = Float64(perf_counter_ns() - start_ns) / 1_000_000.0

            results.append(result)

            # Determine overall status
            if result.status == HealthStatus.UNHEALTHY:
                if check.is_critical():
                    has_critical_failure = True
                elif overall != HealthStatus.UNHEALTHY:
                    overall = HealthStatus.DEGRADED
            elif result.status == HealthStatus.DEGRADED:
                if overall == HealthStatus.HEALTHY:
                    overall = HealthStatus.DEGRADED

        if has_critical_failure:
            overall = HealthStatus.UNHEALTHY

        # Build response
        var response = Dict[String, Any]()
        response["status"] = overall
        response["service"] = self.service_name
        response["version"] = self.version

        var checks_list = List[Dict[String, String]]()
        for result in results:
            checks_list.append(result.to_dict())
        response["checks"] = checks_list

        return response

    fn is_ready(inout self) -> Bool:
        """Quick check if service is ready."""
        var status = self.readiness()
        return status["status"] == HealthStatus.HEALTHY

    fn check_count(self) -> Int:
        """Get number of registered checks."""
        return len(self.checks)


struct SimpleCheck:
    """Simple health check that always returns a fixed status."""

    var _name: String
    var _status: String
    var _critical: Bool

    fn __init__(out self, name: String, status: String = HealthStatus.HEALTHY, critical: Bool = True):
        self._name = name
        self._status = status
        self._critical = critical

    fn name(self) -> String:
        return self._name

    fn check(self) -> CheckResult:
        return CheckResult(self._name, self._status)

    fn is_critical(self) -> Bool:
        return self._critical


fn healthy_check(name: String) -> SimpleCheck:
    """Create a check that always returns healthy."""
    return SimpleCheck(name, HealthStatus.HEALTHY)


fn unhealthy_check(name: String, critical: Bool = True) -> SimpleCheck:
    """Create a check that always returns unhealthy."""
    return SimpleCheck(name, HealthStatus.UNHEALTHY, critical)
