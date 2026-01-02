"""Tests for health checker."""

from testing import assert_true, assert_false, assert_equal
from ..src.checker import HealthChecker, CheckResult, HealthStatus, SimpleCheck, healthy_check, unhealthy_check


fn test_health_status_constants():
    """Health status constants are correct."""
    assert_equal(HealthStatus.HEALTHY, "healthy")
    assert_equal(HealthStatus.UNHEALTHY, "unhealthy")
    assert_equal(HealthStatus.DEGRADED, "degraded")


fn test_check_result_creation():
    """CheckResult can be created."""
    var result = CheckResult("test", HealthStatus.HEALTHY)

    assert_equal(result.name, "test")
    assert_equal(result.status, HealthStatus.HEALTHY)
    assert_true(result.is_healthy())


fn test_check_result_with_message():
    """CheckResult with message."""
    var result = CheckResult("test", HealthStatus.UNHEALTHY, "Connection refused", 10.5)

    assert_equal(result.name, "test")
    assert_equal(result.status, HealthStatus.UNHEALTHY)
    assert_equal(result.message, "Connection refused")
    assert_false(result.is_healthy())


fn test_health_checker_liveness():
    """Liveness returns service info."""
    var health = HealthChecker("my-service", "1.0.0")
    var result = health.liveness()

    assert_equal(result["status"], HealthStatus.HEALTHY)
    assert_equal(result["service"], "my-service")
    assert_equal(result["version"], "1.0.0")


fn test_health_checker_no_checks():
    """Readiness with no checks is healthy."""
    var health = HealthChecker("my-service", "1.0.0")
    var result = health.readiness()

    assert_equal(result["status"], HealthStatus.HEALTHY)


fn test_simple_check():
    """SimpleCheck returns fixed status."""
    var check = SimpleCheck("test", HealthStatus.HEALTHY)

    assert_equal(check.name(), "test")
    assert_true(check.is_critical())

    var result = check.check()
    assert_equal(result.status, HealthStatus.HEALTHY)


fn test_healthy_check_factory():
    """healthy_check creates healthy check."""
    var check = healthy_check("test")
    var result = check.check()

    assert_equal(result.status, HealthStatus.HEALTHY)


fn test_unhealthy_check_factory():
    """unhealthy_check creates unhealthy check."""
    var check = unhealthy_check("test")
    var result = check.check()

    assert_equal(result.status, HealthStatus.UNHEALTHY)


fn test_check_result_to_dict():
    """CheckResult converts to dict."""
    var result = CheckResult("test", HealthStatus.HEALTHY, "OK", 5.5)
    var d = result.to_dict()

    assert_equal(d["name"], "test")
    assert_equal(d["status"], HealthStatus.HEALTHY)
    assert_equal(d["message"], "OK")


fn main():
    """Run all tests."""
    print("Running health checker tests...")

    test_health_status_constants()
    print("  ✓ test_health_status_constants")

    test_check_result_creation()
    print("  ✓ test_check_result_creation")

    test_check_result_with_message()
    print("  ✓ test_check_result_with_message")

    test_health_checker_liveness()
    print("  ✓ test_health_checker_liveness")

    test_health_checker_no_checks()
    print("  ✓ test_health_checker_no_checks")

    test_simple_check()
    print("  ✓ test_simple_check")

    test_healthy_check_factory()
    print("  ✓ test_healthy_check_factory")

    test_unhealthy_check_factory()
    print("  ✓ test_unhealthy_check_factory")

    test_check_result_to_dict()
    print("  ✓ test_check_result_to_dict")

    print("\nAll health checker tests passed!")
