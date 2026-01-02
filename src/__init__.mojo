"""
Mojo Health Check Library

Provides Kubernetes-compatible health checks:
- HealthChecker: Health check aggregation and status
- Probes: Liveness and readiness probe types
- Built-in checks: HTTP, TCP, Database pings

Usage:
    from mojo_health import HealthChecker, pingCheck

    var health = HealthChecker("gateway", "1.0.0")
    health.register(pingCheck("database", db.ping))
    health.register(pingCheck("redis", redis.ping))

    # GET /health - liveness
    print(health.liveness())

    # GET /ready - readiness with checks
    print(health.readiness())
"""

from .checker import HealthChecker, CheckResult, HealthStatus
from .probes import pingCheck, httpCheck, tcpCheck
from .aggregator import HealthAggregator, ServiceHealth
