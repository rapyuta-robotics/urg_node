// Copyright 2026 Rapyuta Robotics Co., Ltd.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#ifndef URG_NODE__NO_RETURN_AS_INF_HPP_
#define URG_NODE__NO_RETURN_AS_INF_HPP_

#include <cmath>
#include <cstddef>
#include <limits>
#include <vector>

namespace urg_node
{

// Raw readings at or above this value (mm) are Hokuyo "no return" codes.
constexpr long kNoReturnRawThresholdMm = 65500;  // NOLINT(runtime/int)

/// Convert one raw reading (mm) to meters, or +inf when the beam has no
/// valid return: raw 0, raw >= kNoReturnRawThresholdMm, or a range outside
/// [range_min, range_max].
inline float rawRangeOrInf(long raw_mm, float range_min, float range_max)  // NOLINT(runtime/int)
{
  if (raw_mm == 0 || raw_mm >= kNoReturnRawThresholdMm) {
    return std::numeric_limits<float>::infinity();
  }
  const float range = static_cast<float>(raw_mm) / 1000.0f;
  if (std::isnan(range) || range < range_min || range > range_max) {
    return std::numeric_limits<float>::infinity();
  }
  return range;
}

/// Fill the echoes of one multiecho beam. A raw 0 ends the echo list (the
/// URG pads unused echoes with 0). Invalid echoes are skipped. When no echo is
/// valid, the beam gets a single +inf echo (intensity 0).
/// intensities may be nullptr; intensity_echoes is then left untouched.
template<typename IntensityT>
void fillEchoesNoReturnAsInf(
  const long * raw_mm, const IntensityT * intensities,  // NOLINT(runtime/int)
  std::size_t max_echo, float range_min, float range_max,
  std::vector<float> & range_echoes, std::vector<float> & intensity_echoes)
{
  bool any_valid = false;
  for (std::size_t j = 0; j < max_echo; j++) {
    if (raw_mm[j] == 0) {
      break;
    }
    const float range = rawRangeOrInf(raw_mm[j], range_min, range_max);
    if (std::isinf(range)) {
      continue;
    }
    range_echoes.push_back(range);
    if (intensities != nullptr) {
      intensity_echoes.push_back(static_cast<float>(intensities[j]));
    }
    any_valid = true;
  }
  if (!any_valid) {
    range_echoes.push_back(std::numeric_limits<float>::infinity());
    if (intensities != nullptr) {
      intensity_echoes.push_back(0.0f);
    }
  }
}

}  // namespace urg_node

#endif  // URG_NODE__NO_RETURN_AS_INF_HPP_
