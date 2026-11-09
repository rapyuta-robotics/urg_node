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

#include <gtest/gtest.h>

#include <cmath>
#include <vector>

#include "urg_node/no_return_as_inf.hpp"

namespace
{
constexpr float kMin = 0.02f;
constexpr float kMax = 30.0f;
}  // namespace

TEST(RawRangeOrInf, ValidReadingIsConvertedToMeters)
{
  EXPECT_FLOAT_EQ(urg_node::rawRangeOrInf(1500, kMin, kMax), 1.5f);
  EXPECT_FLOAT_EQ(urg_node::rawRangeOrInf(20, kMin, kMax), 0.02f);
  EXPECT_FLOAT_EQ(urg_node::rawRangeOrInf(30000, kMin, kMax), 30.0f);
}

TEST(RawRangeOrInf, ZeroIsInf)
{
  EXPECT_TRUE(std::isinf(urg_node::rawRangeOrInf(0, kMin, kMax)));
}

TEST(RawRangeOrInf, NoReturnCodesAreInf)
{
  EXPECT_TRUE(std::isinf(urg_node::rawRangeOrInf(65500, kMin, kMax)));
  EXPECT_TRUE(std::isinf(urg_node::rawRangeOrInf(65533, kMin, kMax)));
  EXPECT_TRUE(std::isinf(urg_node::rawRangeOrInf(65535, kMin, kMax)));
}

TEST(RawRangeOrInf, OutOfSpecIsInf)
{
  EXPECT_TRUE(std::isinf(urg_node::rawRangeOrInf(10, kMin, kMax)));
  EXPECT_TRUE(std::isinf(urg_node::rawRangeOrInf(30001, kMin, kMax)));
  EXPECT_GT(urg_node::rawRangeOrInf(10, kMin, kMax), 0.0f);
}

TEST(FillEchoes, KeepsValidEchoesAndStopsAtZero)
{
  const long raw[] = {1000, 65533, 2000, 0, 3000};  // NOLINT(runtime/int)
  const unsigned short inten[] = {10, 11, 12, 13, 14};  // NOLINT(runtime/int)
  std::vector<float> ranges, intensities;
  urg_node::fillEchoesNoReturnAsInf(raw, inten, 5, kMin, kMax, ranges, intensities);
  ASSERT_EQ(ranges.size(), 2u);
  EXPECT_FLOAT_EQ(ranges[0], 1.0f);
  EXPECT_FLOAT_EQ(ranges[1], 2.0f);
  ASSERT_EQ(intensities.size(), 2u);
  EXPECT_FLOAT_EQ(intensities[0], 10.0f);
  EXPECT_FLOAT_EQ(intensities[1], 12.0f);
}

TEST(FillEchoes, BeamWithoutValidEchoGetsOneInf)
{
  const long raw[] = {65533, 10, 0};  // NOLINT(runtime/int)
  const unsigned short inten[] = {5, 6, 7};  // NOLINT(runtime/int)
  std::vector<float> ranges, intensities;
  urg_node::fillEchoesNoReturnAsInf(raw, inten, 3, kMin, kMax, ranges, intensities);
  ASSERT_EQ(ranges.size(), 1u);
  EXPECT_TRUE(std::isinf(ranges[0]));
  ASSERT_EQ(intensities.size(), 1u);
  EXPECT_FLOAT_EQ(intensities[0], 0.0f);
}

TEST(FillEchoes, NoIntensityLeavesIntensityEchoesEmpty)
{
  const long raw[] = {0, 0, 0};  // NOLINT(runtime/int)
  std::vector<float> ranges, intensities;
  urg_node::fillEchoesNoReturnAsInf<unsigned short>(  // NOLINT(runtime/int)
    raw, nullptr, 3, kMin, kMax, ranges, intensities);
  ASSERT_EQ(ranges.size(), 1u);
  EXPECT_TRUE(std::isinf(ranges[0]));
  EXPECT_TRUE(intensities.empty());
}
