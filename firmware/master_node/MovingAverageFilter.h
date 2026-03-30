#pragma once

#include <Arduino.h>

template <size_t WindowSize>
class MovingAverageFilter {
 public:
  MovingAverageFilter() : sum_(0.0f), count_(0), index_(0) {
    for (size_t i = 0; i < WindowSize; ++i) {
      samples_[i] = 0.0f;
    }
  }

  void reset(float seedValue = 0.0f) {
    sum_ = 0.0f;
    count_ = 0;
    index_ = 0;
    for (size_t i = 0; i < WindowSize; ++i) {
      samples_[i] = 0.0f;
    }

    add(seedValue);
  }

  float add(float sample) {
    if (count_ < WindowSize) {
      samples_[index_] = sample;
      sum_ += sample;
      ++count_;
      index_ = (index_ + 1U) % WindowSize;
      return average();
    }

    sum_ -= samples_[index_];
    samples_[index_] = sample;
    sum_ += sample;
    index_ = (index_ + 1U) % WindowSize;
    return average();
  }

  float average() const {
    if (count_ == 0U) {
      return 0.0f;
    }
    return sum_ / static_cast<float>(count_);
  }

  bool isPrimed() const {
    return count_ == WindowSize;
  }

 private:
  float samples_[WindowSize];
  float sum_;
  size_t count_;
  size_t index_;
};
