"""
Health Aggregator for Multi-Service Monitoring

Aggregates health status from multiple services.
Useful for gateway/orchestrator services.

Example:
    var aggregator = HealthAggregator()
    aggregator.register("auth", "http://auth:8080/health")
    aggregator.register("search", "http://search:8080/health")

    # Get aggregated health
    var status = aggregator.check_all()
    # {"overall": "healthy", "services": {...}}
"""

from time import perf_counter_ns
from python import Python
from .checker import CheckResult, HealthStatus


@value
struct ServiceHealth:
    """Health status for a single service."""

    var name: String
    """Service name."""

    var url: String
    """Health endpoint URL."""

    var status: String
    """Current health status."""

    var last_check_ns: Int
    """Timestamp of last check."""

    var latency_ms: Float64
    """Last check latency."""

    var message: String
    """Status message."""

    fn __init__(out self, name: String, url: String):
        """Create service health tracker."""
        self.name = name
        self.url = url
        self.status = HealthStatus.HEALTHY
        self.last_check_ns = 0
        self.latency_ms = 0.0
        self.message = ""

    fn is_healthy(self) -> Bool:
        """Check if service is healthy."""
        return self.status == HealthStatus.HEALTHY

    fn is_stale(self, max_age_ns: Int) -> Bool:
        """Check if last check is stale."""
        if self.last_check_ns == 0:
            return True
        return perf_counter_ns() - self.last_check_ns > max_age_ns


struct HealthAggregator:
    """
    Multi-service health aggregator.

    Monitors health of multiple services and aggregates status.
    """

    var services: Dict[String, ServiceHealth]
    """Registered services."""

    var check_timeout_ms: Int
    """Timeout for health checks."""

    var cache_duration_ms: Int
    """How long to cache health status."""

    fn __init__(out self, check_timeout_ms: Int = 5000, cache_duration_ms: Int = 10000):
        """Create aggregator."""
        self.services = Dict[String, ServiceHealth]()
        self.check_timeout_ms = check_timeout_ms
        self.cache_duration_ms = cache_duration_ms

    fn register(inout self, name: String, health_url: String):
        """Register a service to monitor."""
        self.services[name] = ServiceHealth(name, health_url)

    fn unregister(inout self, name: String):
        """Unregister a service."""
        if name in self.services:
            _ = self.services.pop(name)

    fn check_service(inout self, name: String) -> ServiceHealth:
        """Check health of a specific service."""
        if name not in self.services:
            var unknown = ServiceHealth(name, "")
            unknown.status = HealthStatus.UNHEALTHY
            unknown.message = "Service not registered"
            return unknown

        var service = self.services[name]
        var start_ns = perf_counter_ns()

        try:
            var httpx = Python.import_module("httpx")
            var timeout = Float64(self.check_timeout_ms) / 1000.0
            var response = httpx.get(service.url, timeout=timeout)

            service.latency_ms = Float64(perf_counter_ns() - start_ns) / 1_000_000.0
            service.last_check_ns = perf_counter_ns()

            var status_code = int(response.status_code)
            if status_code >= 200 and status_code < 300:
                service.status = HealthStatus.HEALTHY
                service.message = "HTTP " + str(status_code)
            else:
                service.status = HealthStatus.UNHEALTHY
                service.message = "HTTP " + str(status_code)
        except e:
            service.latency_ms = Float64(perf_counter_ns() - start_ns) / 1_000_000.0
            service.last_check_ns = perf_counter_ns()
            service.status = HealthStatus.UNHEALTHY
            service.message = "Check failed: " + str(e)

        self.services[name] = service
        return service

    fn check_all(inout self) -> Dict[String, Any]:
        """
        Check all registered services.

        Returns aggregated status.
        """
        var results = Dict[String, ServiceHealth]()
        var overall = HealthStatus.HEALTHY
        var healthy_count = 0
        var total_count = 0

        for name in self.services:
            total_count += 1
            var health = self.check_service(name)
            results[name] = health

            if health.status == HealthStatus.HEALTHY:
                healthy_count += 1
            elif health.status == HealthStatus.UNHEALTHY:
                overall = HealthStatus.UNHEALTHY
            elif health.status == HealthStatus.DEGRADED:
                if overall != HealthStatus.UNHEALTHY:
                    overall = HealthStatus.DEGRADED

        var response = Dict[String, Any]()
        response["overall"] = overall
        response["healthy"] = healthy_count
        response["total"] = total_count

        var services_dict = Dict[String, Dict[String, String]]()
        for name in results:
            var service = results[name]
            var svc_info = Dict[String, String]()
            svc_info["status"] = service.status
            svc_info["latency_ms"] = str(service.latency_ms)
            svc_info["message"] = service.message
            services_dict[name] = svc_info

        response["services"] = services_dict

        return response

    fn get_cached(inout self, name: String) -> ServiceHealth:
        """
        Get cached health status for service.

        Checks if cache is stale and refreshes if needed.
        """
        if name not in self.services:
            var unknown = ServiceHealth(name, "")
            unknown.status = HealthStatus.UNHEALTHY
            unknown.message = "Service not registered"
            return unknown

        var service = self.services[name]
        var cache_duration_ns = self.cache_duration_ms * 1_000_000

        if service.is_stale(cache_duration_ns):
            return self.check_service(name)

        return service

    fn is_all_healthy(inout self) -> Bool:
        """Quick check if all services are healthy."""
        for name in self.services:
            var health = self.get_cached(name)
            if not health.is_healthy():
                return False
        return True

    fn service_count(self) -> Int:
        """Get number of registered services."""
        return len(self.services)


struct DependencyChecker:
    """
    Checks dependencies required for service startup.

    Use during initialization to verify all dependencies are available.
    """

    var dependencies: List[String]
    """Dependency health URLs."""

    var timeout_ms: Int
    """Check timeout."""

    var retry_count: Int
    """Number of retries."""

    var retry_delay_ms: Int
    """Delay between retries."""

    fn __init__(out self, timeout_ms: Int = 5000, retry_count: Int = 3, retry_delay_ms: Int = 1000):
        """Create dependency checker."""
        self.dependencies = List[String]()
        self.timeout_ms = timeout_ms
        self.retry_count = retry_count
        self.retry_delay_ms = retry_delay_ms

    fn add(inout self, health_url: String):
        """Add a dependency to check."""
        self.dependencies.append(health_url)

    fn wait_for_all(self) raises -> Bool:
        """
        Wait for all dependencies to be healthy.

        Retries until all dependencies pass or max retries exceeded.
        """
        var httpx = Python.import_module("httpx")
        var time = Python.import_module("time")
        var timeout = Float64(self.timeout_ms) / 1000.0

        for attempt in range(self.retry_count):
            var all_healthy = True

            for url in self.dependencies:
                try:
                    var response = httpx.get(url, timeout=timeout)
                    if int(response.status_code) >= 300:
                        all_healthy = False
                        break
                except:
                    all_healthy = False
                    break

            if all_healthy:
                return True

            if attempt < self.retry_count - 1:
                time.sleep(Float64(self.retry_delay_ms) / 1000.0)

        return False
