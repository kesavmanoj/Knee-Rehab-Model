from __future__ import annotations

import math


def solve_linear_system(matrix: list[list[float]], values: list[float]) -> list[float]:
    size = len(values)
    for pivot_index in range(size):
        max_row = max(range(pivot_index, size), key=lambda row: abs(matrix[row][pivot_index]))
        if abs(matrix[max_row][pivot_index]) < 1e-12:
            raise ValueError("Singular system while fitting calibration curve.")

        if max_row != pivot_index:
            matrix[pivot_index], matrix[max_row] = matrix[max_row], matrix[pivot_index]
            values[pivot_index], values[max_row] = values[max_row], values[pivot_index]

        pivot = matrix[pivot_index][pivot_index]
        for column in range(pivot_index, size):
            matrix[pivot_index][column] /= pivot
        values[pivot_index] /= pivot

        for row in range(size):
            if row == pivot_index:
                continue
            factor = matrix[row][pivot_index]
            if factor == 0.0:
                continue
            for column in range(pivot_index, size):
                matrix[row][column] -= factor * matrix[pivot_index][column]
            values[row] -= factor * values[pivot_index]

    return values


def polyfit(xs: list[float], ys: list[float], degree: int) -> list[float]:
    size = degree + 1
    power_sums = [sum(x ** power for x in xs) for power in range((2 * degree) + 1)]
    matrix = [[0.0] * size for _ in range(size)]
    values = [0.0] * size

    for row in range(size):
        for column in range(size):
            matrix[row][column] = power_sums[row + column]
        values[row] = sum((x ** row) * y for x, y in zip(xs, ys))

    coefficients_low_to_high = solve_linear_system(matrix, values)
    return list(reversed(coefficients_low_to_high))


def polyval(coefficients: list[float], x_value: float) -> float:
    result = 0.0
    for coefficient in coefficients:
        result = (result * x_value) + coefficient
    return result


def rmse(coefficients: list[float], xs: list[float], ys: list[float]) -> float:
    return math.sqrt(sum((polyval(coefficients, x_value) - y_value) ** 2 for x_value, y_value in zip(xs, ys)) / len(xs))
