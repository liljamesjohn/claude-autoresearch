"""
Toy sorting module with a deliberately inefficient implementation.
This is the file autoresearch should optimize.
"""


def sort_numbers(numbers: list[int]) -> list[int]:
    """Sort a list of integers. Currently uses bubble sort (O(n^2))."""
    result = list(numbers)  # copy to avoid mutation
    n = len(result)
    for i in range(n):
        for j in range(0, n - i - 1):
            if result[j] > result[j + 1]:
                result[j], result[j + 1] = result[j + 1], result[j]
    return result


def find_median(numbers: list[int]) -> float:
    """Find the median of a list of integers."""
    sorted_nums = sort_numbers(numbers)
    n = len(sorted_nums)
    if n % 2 == 0:
        return (sorted_nums[n // 2 - 1] + sorted_nums[n // 2]) / 2
    return sorted_nums[n // 2]


def find_percentile(numbers: list[int], p: float) -> float:
    """Find the p-th percentile (0-100) of a list of integers."""
    if not 0 <= p <= 100:
        raise ValueError("Percentile must be between 0 and 100")
    sorted_nums = sort_numbers(numbers)
    n = len(sorted_nums)
    k = (p / 100) * (n - 1)
    f = int(k)
    c = f + 1
    if c >= n:
        return sorted_nums[f]
    return sorted_nums[f] + (k - f) * (sorted_nums[c] - sorted_nums[f])
