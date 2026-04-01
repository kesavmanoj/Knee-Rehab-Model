#pragma once

namespace GeneratedCalibration {

static constexpr char kPotSourceSession[] = "pot_session_20260331_191852";
static constexpr float kPotRawAdcSlope = 0.066298363454f;
static constexpr float kPotRawAdcIntercept = -10.941682176146f;
static constexpr float kPotFitRmseDeg = 0.553146395303f;

static constexpr char kFlexSourceSession[] = "flex_session_20260331_201536";
static constexpr int kFlexSelectedPolynomialDegree = 2;
static constexpr float kFlexQuadraticCoefficients[3] = {0.000119781839f, -0.347271990929f, 247.106218746343f};
static constexpr float kFlexQuadraticRmseDeg = 2.495850081888f;
static constexpr float kFlexCubicCoefficients[4] = {0.000000167175f, -0.000927524579f, 1.813489619872f, -1219.871075226469f};
static constexpr float kFlexCubicRmseDeg = 1.285905736642f;

static constexpr char kImuSourceSession[] = "direct_measurement";
static constexpr float kImuRawAngleSlope = 1.000000000000f;
static constexpr float kImuRawAngleIntercept = 0.000000000000f;
static constexpr float kImuFitRmseDeg = 0.000000000000f;

}  // namespace GeneratedCalibration
