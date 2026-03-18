"""Correctness tests for the sort module. These must always pass."""

from sort import sort_numbers, find_median, find_percentile


def test_sort_empty():
    assert sort_numbers([]) == []


def test_sort_single():
    assert sort_numbers([42]) == [42]


def test_sort_already_sorted():
    assert sort_numbers([1, 2, 3, 4, 5]) == [1, 2, 3, 4, 5]


def test_sort_reversed():
    assert sort_numbers([5, 4, 3, 2, 1]) == [1, 2, 3, 4, 5]


def test_sort_duplicates():
    assert sort_numbers([3, 1, 4, 1, 5, 9, 2, 6, 5, 3]) == [1, 1, 2, 3, 3, 4, 5, 5, 6, 9]


def test_sort_negative():
    assert sort_numbers([-3, -1, -4, -1, -5]) == [-5, -4, -3, -1, -1]


def test_sort_mixed():
    assert sort_numbers([-2, 0, 3, -1, 5]) == [-2, -1, 0, 3, 5]


def test_sort_large():
    import random
    random.seed(42)
    data = random.sample(range(10000), 1000)
    result = sort_numbers(data)
    assert result == sorted(data)


def test_sort_does_not_mutate():
    original = [3, 1, 2]
    sort_numbers(original)
    assert original == [3, 1, 2]


def test_median_odd():
    assert find_median([3, 1, 2]) == 2


def test_median_even():
    assert find_median([4, 1, 3, 2]) == 2.5


def test_median_single():
    assert find_median([7]) == 7


def test_percentile_0():
    assert find_percentile([10, 20, 30, 40, 50], 0) == 10


def test_percentile_100():
    assert find_percentile([10, 20, 30, 40, 50], 100) == 50


def test_percentile_50():
    assert find_percentile([10, 20, 30, 40, 50], 50) == 30


def test_percentile_25():
    result = find_percentile([10, 20, 30, 40, 50], 25)
    assert result == 20.0


def test_percentile_invalid():
    try:
        find_percentile([1, 2, 3], 101)
        assert False, "Should have raised ValueError"
    except ValueError:
        pass


if __name__ == "__main__":
    import sys
    tests = [v for k, v in globals().items() if k.startswith("test_")]
    passed = failed = 0
    for t in tests:
        try:
            t()
            passed += 1
        except Exception as e:
            failed += 1
            print(f"FAIL: {t.__name__}: {e}")
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)
