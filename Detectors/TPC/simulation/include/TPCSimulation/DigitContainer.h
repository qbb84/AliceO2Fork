// Copyright CERN and copyright holders of ALICE O2. This software is
// distributed under the terms of the GNU General Public License v3 (GPL
// Version 3), copied verbatim in the file "COPYING".
//
// See http://alice-o2.web.cern.ch/license for full licensing information.
//
// In applying this license CERN does not waive the privileges and immunities
// granted to it by virtue of its status as an Intergovernmental Organization
// or submit itself to any jurisdiction.

/// \file DigitContainer.h
/// \brief Definition of the Digit Container
/// \author Andi Mathis, TU München, andreas.mathis@ph.tum.de

#ifndef ALICEO2_TPC_DigitContainer_H_
#define ALICEO2_TPC_DigitContainer_H_

#include <deque>
#include "TPCBase/CRU.h"
#include "DataFormatsTPC/Defs.h"
#include "TPCSimulation/DigitTime.h"
#include "TPCBase/ParameterDetector.h"
#include "TPCBase/ParameterElectronics.h"
#include "TPCBase/ParameterGas.h"

namespace o2
{
namespace TPC
{

class Digit;
class DigitMCMetaData;

/// \class DigitContainer
/// This is the base class of the intermediate Digit Containers, in which all incoming electrons from the hits are
/// sorted into after amplification
/// The structure assures proper sorting of the Digits when later on written out for further processing.
/// This class holds the CRU containers.

class DigitContainer
{
 public:
  /// Default constructor
  DigitContainer();

  /// Destructor
  ~DigitContainer() = default;

  /// Reset the container
  void reset();

  /// Set the start time of the first event
  /// \param time Time of the first event
  void setStartTime(TimeBin time) { mFirstTimeBin = time; }

  /// Add digit to the container
  /// \param eventID MC Event ID
  /// \param trackID MC Track ID
  /// \param cru CRU of the digit
  /// \param globalPad Global pad number of the digit
  /// \param timeBin Time bin of the digit
  /// \param signal Charge of the digit in ADC counts
  void addDigit(const MCCompLabel& label, const CRU& cru, TimeBin timeBin, GlobalPadNumber globalPad, float signal);

  /// Fill output vector
  /// \param output Output container
  /// \param mcTruth MC Truth container
  /// \param sector Sector to be processed
  /// \param eventTime time stamp of the event
  /// \param isContinuous Switch for continuous readout
  /// \param finalFlush Flag whether the whole container is dumped
  void fillOutputContainer(std::vector<Digit>& output, dataformats::MCTruthContainer<MCCompLabel>& mcTruth, const Sector& sector, TimeBin eventTime = 0, bool isContinuous = true, bool finalFlush = false);

 private:
  TimeBin mFirstTimeBin;           ///< First time bin to consider
  TimeBin mEffectiveTimeBin;       ///< Effective time bin of that digit
  TimeBin mTmaxTriggered;          ///< Maximum time bin in case of triggered mode (hard cut at average drift speed with additional margin)
  std::deque<DigitTime> mTimeBins; ///< Time bin Container for the ADC value
};

inline DigitContainer::DigitContainer() : mFirstTimeBin(0), mEffectiveTimeBin(0), mTmaxTriggered(0), mTimeBins(500)
{
  const static ParameterDetector& detParam = ParameterDetector::defaultInstance();
  mTmaxTriggered = detParam.getMaxTimeBinTriggered();
}

inline void DigitContainer::reset()
{
  mFirstTimeBin = 0;
  mEffectiveTimeBin = 0;
  for (auto& time : mTimeBins) {
    time.reset();
  }
}
} // namespace TPC
} // namespace o2

#endif // ALICEO2_TPC_DigitContainer_H_
