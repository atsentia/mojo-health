"""
Built-in Health Check Probes

Provides common health check implementations:
- pingCheck: Call a ping function
- httpCheck: HTTP endpoint health
- tcpCheck: TCP connectivity
- customCheck: Custom check function

Example:
    # Ping-based check
    health.register(pingCheck("database", db.ping))

    # HTTP endpoint check
    health.register(httpCheck("auth-service", "http://auth:8080/health"))

    # TCP connectivity check
    health.register(tcpCheck("redis", "redis:6379"))
"""

from time import perf_counter_ns
from python import Python
from .checker import CheckResult, HealthStatus, HealthCheck


struct PingCheck:
    """
    Health check that calls a ping function.

    The ping function should return True for healthy, False for unhealthy.
    """

    var _name: String
    var _ping_fn: fn() -> Bool
    var _critical: Bool
    var _timeout_ms: Int

    fn __init__(
        inout self,
        name: String,
        ping_fn: fn() -> Bool,
        critical: Bool = True,
        timeout_ms: Int = 5000,
    ):
        self._name = name
        self._ping_fn = ping_fn
        self._critical = critical
        self._timeout_ms = timeout_ms

    fn name(self) -> String:
        return self._name

    fn check(self) -> CheckResult:
        var start_ns = perf_counter_ns()

        try:
            var healthy = self._ping_fn()
            var latency_ms = Float64(perf_counter_ns() - start_ns) / 1_000_000.0

            if healthy:
                return CheckResult(
                    self._name,
                    HealthStatus.HEALTHY,
                    "ping successful",
                    latency_ms,
                )
            else:
                return CheckResult(
                    self._name,
                    HealthStatus.UNHEALTHY,
                    "ping returned false",
                    latency_ms,
                )
        except e:
            var latency_ms = Float64(perf_counter_ns() - start_ns) / 1_000_000.0
            return CheckResult(
                self._name,
                HealthStatus.UNHEALTHY,
                "ping failed: " + str(e),
                latency_ms,
            )

    fn is_critical(self) -> Bool:
        return self._critical


fn pingCheck(name: String, ping_fn: fn() -> Bool) -> PingCheck:
    """Create a ping-based health check."""
    return PingCheck(name, ping_fn)


struct HttpCheck:
    """
    Health check that calls an HTTP endpoint.

    Expects 2xx response for healthy status.
    Uses Python httpx for HTTP requests.
    """

    var _name: String
    var _url: String
    var _critical: Bool
    var _timeout_ms: Int
    var _expected_status: Int

    fn __init__(
        inout self,
        name: String,
        url: String,
        critical: Bool = True,
        timeout_ms: Int = 5000,
        expected_status: Int = 200,
    ):
        self._name = name
        self._url = url
        self._critical = critical
        self._timeout_ms = timeout_ms
        self._expected_status = expected_status

    fn name(self) -> String:
        return self._name

    fn check(self) -> CheckResult:
        var start_ns = perf_counter_ns()

        try:
            var httpx = Python.import_module("httpx")
            var timeout = Float64(self._timeout_ms) / 1000.0
            var response = httpx.get(self._url, timeout=timeout)

            var latency_ms = Float64(perf_counter_ns() - start_ns) / 1_000_000.0
            var status_code = int(response.status_code)

            if status_code >= 200 and status_code < 300:
                return CheckResult(
                    self._name,
                    HealthStatus.HEALTHY,
                    "HTTP " + str(status_code),
                    latency_ms,
                )
            else:
                return CheckResult(
                    self._name,
                    HealthStatus.UNHEALTHY,
                    "HTTP " + str(status_code),
                    latency_ms,
                )
        except e:
            var latency_ms = Float64(perf_counter_ns() - start_ns) / 1_000_000.0
            return CheckResult(
                self._name,
                HealthStatus.UNHEALTHY,
                "HTTP check failed: " + str(e),
                latency_ms,
            )

    fn is_critical(self) -> Bool:
        return self._critical


fn httpCheck(name: String, url: String) -> HttpCheck:
    """Create an HTTP health check."""
    return HttpCheck(name, url)


struct TcpCheck:
    """
    Health check that tests TCP connectivity.

    Uses Python socket for connectivity test.
    """

    var _name: String
    var _host: String
    var _port: Int
    var _critical: Bool
    var _timeout_ms: Int

    fn __init__(
        inout self,
        name: String,
        host: String,
        port: Int,
        critical: Bool = True,
        timeout_ms: Int = 5000,
    ):
        self._name = name
        self._host = host
        self._port = port
        self._critical = critical
        self._timeout_ms = timeout_ms

    fn __init__(
        inout self,
        name: String,
        address: String,  # "host:port" format
        critical: Bool = True,
        timeout_ms: Int = 5000,
    ):
        self._name = name
        self._critical = critical
        self._timeout_ms = timeout_ms

        # Parse "host:port"
        var parts = address.split(":")
        if len(parts) == 2:
            self._host = parts[0]
            self._port = int(parts[1])
        else:
            self._host = address
            self._port = 80

    fn name(self) -> String:
        return self._name

    fn check(self) -> CheckResult:
        var start_ns = perf_counter_ns()

        try:
            var socket = Python.import_module("socket")
            var timeout = Float64(self._timeout_ms) / 1000.0

            var sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)

            var result = sock.connect_ex((self._host, self._port))
            sock.close()

            var latency_ms = Float64(perf_counter_ns() - start_ns) / 1_000_000.0

            if int(result) == 0:
                return CheckResult(
                    self._name,
                    HealthStatus.HEALTHY,
                    "TCP connection successful",
                    latency_ms,
                )
            else:
                return CheckResult(
                    self._name,
                    HealthStatus.UNHEALTHY,
                    "TCP connection failed: error " + str(result),
                    latency_ms,
                )
        except e:
            var latency_ms = Float64(perf_counter_ns() - start_ns) / 1_000_000.0
            return CheckResult(
                self._name,
                HealthStatus.UNHEALTHY,
                "TCP check failed: " + str(e),
                latency_ms,
            )

    fn is_critical(self) -> Bool:
        return self._critical


fn tcpCheck(name: String, address: String) -> TcpCheck:
    """Create a TCP connectivity health check."""
    return TcpCheck(name, address)


struct CustomCheck:
    """
    Health check with custom check function.

    The function returns (status, message) tuple.
    """

    var _name: String
    var _check_fn: fn() -> (String, String)
    var _critical: Bool

    fn __init__(
        inout self,
        name: String,
        check_fn: fn() -> (String, String),
        critical: Bool = True,
    ):
        self._name = name
        self._check_fn = check_fn
        self._critical = critical

    fn name(self) -> String:
        return self._name

    fn check(self) -> CheckResult:
        var start_ns = perf_counter_ns()

        try:
            var result = self._check_fn()
            var status = result[0]
            var message = result[1]
            var latency_ms = Float64(perf_counter_ns() - start_ns) / 1_000_000.0

            return CheckResult(self._name, status, message, latency_ms)
        except e:
            var latency_ms = Float64(perf_counter_ns() - start_ns) / 1_000_000.0
            return CheckResult(
                self._name,
                HealthStatus.UNHEALTHY,
                "Check failed: " + str(e),
                latency_ms,
            )

    fn is_critical(self) -> Bool:
        return self._critical


fn customCheck(name: String, check_fn: fn() -> (String, String)) -> CustomCheck:
    """Create a custom health check."""
    return CustomCheck(name, check_fn)
