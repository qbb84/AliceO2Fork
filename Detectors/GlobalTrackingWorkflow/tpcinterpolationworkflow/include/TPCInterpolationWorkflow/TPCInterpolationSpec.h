// Copyright 2019-2020 CERN and copyright holders of ALICE O2.
// See https://alice-o2.web.cern.ch/copyright for details of the copyright holders.
// All rights not expressly granted are reserved.
//
// This software is distributed under the terms of the GNU General Public
// License v3 (GPL Version 3), copied verbatim in the file "COPYING".
//
// In applying this license CERN does not waive the privileges and immunities
// granted to it by virtue of its status as an Intergovernmental Organization
// or submit itself to any jurisdiction.

#ifndef O2_TPC_INTERPOLATION_SPEC_H
#define O2_TPC_INTERPOLATION_SPEC_H

/// @file   TPCInterpolationSpec.h

#include "DataFormatsTPC/Constants.h"
#include "SpacePoints/TrackInterpolation.h"
#include "Framework/DataProcessorSpec.h"
#include "Framework/Task.h"
#include "TStopwatch.h"
#include "ReconstructionDataFormats/GlobalTrackID.h"
#include "DetectorsBase/GRPGeomHelper.h"
#include "TPCCalibration/VDriftHelper.h"
#include "DataFormatsITSMFT/TopologyDictionary.h"

using namespace o2::framework;

namespace o2::globaltracking
{
struct DataRequest;
} // namespace o2::globaltracking

namespace o2
{
namespace tpc
{
class TPCInterpolationDPL : public Task
{
 public:
  TPCInterpolationDPL(std::shared_ptr<o2::globaltracking::DataRequest> dr, o2::dataformats::GlobalTrackID::mask_t src, std::shared_ptr<o2::base::GRPGeomRequest> gr, bool useMC, bool processITSTPConly, bool sendTrackData, bool debugOutput) : mDataRequest(dr), mSources(src), mGGCCDBRequest(gr), mUseMC(useMC), mProcessITSTPConly(processITSTPConly), mSendTrackData(sendTrackData), mDebugOutput(debugOutput) {}
  ~TPCInterpolationDPL() override = default;
  void init(InitContext& ic) final;
  void run(ProcessingContext& pc) final;
  void endOfStream(EndOfStreamContext& ec) final;
  void finaliseCCDB(ConcreteDataMatcher& matcher, void* obj) final;

 private:
  void updateTimeDependentParams(ProcessingContext& pc);
  o2::tpc::TrackInterpolation mInterpolation;                    ///< track interpolation engine
  std::shared_ptr<o2::globaltracking::DataRequest> mDataRequest; ///< steers the input
  std::shared_ptr<o2::base::GRPGeomRequest> mGGCCDBRequest;
  o2::tpc::VDriftHelper mTPCVDriftHelper{};
  const o2::itsmft::TopologyDictionary* mITSDict = nullptr; ///< cluster patterns dictionary
  o2::dataformats::GlobalTrackID::mask_t mSources{};        ///< which input sources are configured
  bool mUseMC{false}; ///< MC flag
  bool mProcessITSTPConly{false}; ///< should also tracks without outer point (ITS-TPC only) be processed?
  bool mProcessSeeds{false};      ///< process not only most complete track, but also its shorter parts
  bool mDebugOutput{false};       ///< add more information to the output (track points of ITS, TRD and TOF)
  bool mSendTrackData{false};     ///< if true, not only the clusters but also corresponding track data will be sent
  uint32_t mSlotLength{600u};     ///< the length of one calibration slot required to calculate max number of tracks per TF
  int mMatCorr{2};                ///< the material correction to be used for track interpolation
  TStopwatch mTimer;
};

/// create a processor spec
framework::DataProcessorSpec getTPCInterpolationSpec(o2::dataformats::GlobalTrackID::mask_t srcCls, o2::dataformats::GlobalTrackID::mask_t srcVtx, o2::dataformats::GlobalTrackID::mask_t srcTrk, bool useMC, bool processITSTPConly, bool sendTrackData, bool debugOutput);

} // namespace tpc
} // namespace o2

#endif
